// skillpatch — inspect / edit an FWSkillDefinition's ChildSkills array (UAssetAPI).
//
//   skillpatch inspect <in.uasset> <usmap>
//   skillpatch imports <in.uasset> <usmap>
//   skillpatch dump    <in.uasset> <usmap>                                          (recursive property tree)
//   skillpatch patch   <in.uasset> <usmap> <out.uasset> <removeName> ...            (remove children by name)
//   skillpatch add     <in.uasset> <usmap> <out.uasset> "<pkgPath>|<objName>" ...   (append cross-package children)
//
// The `add` mode synthesises the import chain (a CoreUObject Package import for the target
// package + an FWSkillDefinition object import) so a skill that currently references no other
// skill (e.g. a dead-end rig node) can be pointed at one in another package. Used to graft
// OldMan's Pack Mule rig line onto the end of ScavGirl's native rig line without duplicating
// the Equipment Runner nodes.
using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.PropertyTypes.Objects;
using UAssetAPI.PropertyTypes.Structs;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

class Program
{
    static string S(FName n) => n?.Value?.Value ?? "<null>";

    static int Main(string[] args)
    {
        if (args.Length < 3) { Console.WriteLine("usage: skillpatch <inspect|imports|patch|add> <in.uasset> <usmap> [...]"); return 1; }
        var mode = args[0];
        var inPath = args[1];
        var usmap = new Usmap(args[2]);
        var asset = new UAsset(inPath, EngineVersion.VER_UE5_4, usmap);

        string NameOf(FPackageIndex idx)
        {
            if (idx == null || idx.Index == 0) return "<null>";
            if (idx.IsImport()) return S(idx.ToImport(asset)?.ObjectName);
            return S(idx.ToExport(asset)?.ObjectName);
        }

        var normals = asset.Exports.OfType<NormalExport>().ToList();

        if (mode == "imports")
        {
            for (int i = 0; i < asset.Imports.Count; i++)
            {
                var im = asset.Imports[i];
                Console.WriteLine($"  import[{i}] fpi={-(i + 1)}  {S(im.ClassPackage)}.{S(im.ClassName)}  outer={NameOf(im.OuterIndex)}  obj={S(im.ObjectName)}");
            }
            foreach (var e in normals)
                Console.WriteLine($"[export {S(e.ObjectName)}] class={NameOf(e.ClassIndex)}");
            return 0;
        }

        if (mode == "dump")
        {
            // Recursive property tree. Authoring a clone means editing nested structs (a GE's granted
            // tags sit two levels down, in two separate containers), and guessing how UAssetAPI models
            // them is how you corrupt an asset. Look first.
            string ValueString(PropertyData p)
            {
                var prop = p.GetType().GetProperty("Value");
                var v = prop?.GetValue(p);
                if (v == null) return "<null>";
                if (v is System.Collections.IEnumerable en && v is not string)
                    return "[" + string.Join(", ", en.Cast<object>().Select(x => x?.ToString() ?? "null")) + "]";
                return v.ToString();
            }

            void DumpProp(PropertyData p, string ind)
            {
                switch (p)
                {
                    case StructPropertyData sp:
                        Console.WriteLine($"{ind}{S(p.Name)} : Struct<{S(sp.StructType)}>");
                        foreach (var c in sp.Value) DumpProp(c, ind + "  ");
                        break;
                    case ArrayPropertyData ap:
                        Console.WriteLine($"{ind}{S(p.Name)} : Array<{S(ap.ArrayType)}>[{ap.Value.Length}]");
                        foreach (var c in ap.Value) DumpProp(c, ind + "  ");
                        break;
                    case ObjectPropertyData op:
                        Console.WriteLine($"{ind}{S(p.Name)} : Object -> {NameOf(op.Value)}");
                        break;
                    default:
                        Console.WriteLine($"{ind}{S(p.Name)} : {p.GetType().Name} = {ValueString(p)}");
                        break;
                }
            }

            for (int i = 0; i < asset.Exports.Count; i++)
            {
                var ex = asset.Exports[i];
                Console.WriteLine($"[export {i}] {S(ex.ObjectName)}  class={NameOf(ex.ClassIndex)}  outer={NameOf(ex.OuterIndex)}  type={ex.GetType().Name}");
                if (ex is NormalExport ne) foreach (var p in ne.Data) DumpProp(p, "    ");
            }
            // The name map matters for cloning: export names and the package path live here, so a
            // rename is mostly "rewrite these entries" rather than "rebuild the asset".
            var names = asset.GetNameMapIndexList();
            Console.WriteLine($"[names] {names.Count} entries");
            for (int i = 0; i < names.Count; i++) Console.WriteLine($"    name[{i}] {names[i].Value}");
            return 0;
        }

        if (mode == "inspect")
        {
            foreach (var e in normals)
            {
                var arr = e.Data.FirstOrDefault(p => S(p.Name) == "ChildSkills") as ArrayPropertyData;
                if (arr == null) { Console.WriteLine($"[{S(e.ObjectName)}] (no ChildSkills)"); continue; }
                Console.WriteLine($"[{S(e.ObjectName)}] ChildSkills = {arr.Value.Length}");
                foreach (var it in arr.Value)
                    Console.WriteLine($"    {(it is ObjectPropertyData op ? NameOf(op.Value) : it.GetType().Name)}");
            }
            return 0;
        }

        if (mode == "patch")   // remove named children
        {
            var outPath = args[3];
            var remove = new HashSet<string>(args.Skip(4), StringComparer.OrdinalIgnoreCase);
            int removed = 0;
            foreach (var e in normals)
            {
                var arr = e.Data.FirstOrDefault(p => S(p.Name) == "ChildSkills") as ArrayPropertyData;
                if (arr == null) continue;
                int before = arr.Value.Length;
                var kept = new List<PropertyData>();
                foreach (var it in arr.Value)
                {
                    if (it is ObjectPropertyData op && remove.Contains(NameOf(op.Value)))
                    { Console.WriteLine($"  - remove {NameOf(op.Value)}"); removed++; continue; }
                    kept.Add(it);
                }
                arr.Value = kept.ToArray();
                if (before != arr.Value.Length) Console.WriteLine($"[{S(e.ObjectName)}] ChildSkills: {before} -> {arr.Value.Length}");
            }
            asset.Write(outPath);
            Console.WriteLine($"removed {removed}; wrote {outPath}");
            return removed == remove.Count ? 0 : 3;
        }

        if (mode == "add")     // append cross-package children (synthesises the import chain)
        {
            var outPath = args[3];
            var specs = args.Skip(4).ToList();   // each "<pkgPath>|<objName>"
            if (specs.Count == 0) { Console.WriteLine("no children to add"); return 1; }

            // the skill export (class FWSkillDefinition); reuse its class/module names for new imports
            var e = normals.FirstOrDefault(x => x.ClassIndex.IsImport() && S(x.ClassIndex.ToImport(asset)?.ObjectName) == "FWSkillDefinition")
                    ?? normals.First();
            var classImp = e.ClassIndex.ToImport(asset);
            string className = S(classImp.ObjectName);                             // FWSkillDefinition
            string classPkg  = S(classImp.OuterIndex.ToImport(asset).ObjectName);  // /Script/<Module>
            string coreU     = S(classImp.ClassPackage);                           // /Script/CoreUObject

            FPackageIndex FindOrAddImport(string cPkg, string cName, FPackageIndex outer, string objName)
            {
                for (int i = 0; i < asset.Imports.Count; i++)
                {
                    var im = asset.Imports[i];
                    if (S(im.ObjectName) == objName && S(im.ClassName) == cName && S(im.ClassPackage) == cPkg &&
                        (im.OuterIndex?.Index ?? 0) == (outer?.Index ?? 0))
                        return new FPackageIndex(-(i + 1));
                }
                var imp = new Import(FName.FromString(asset, cPkg), FName.FromString(asset, cName),
                                     outer, FName.FromString(asset, objName), false);
                asset.Imports.Add(imp);
                return new FPackageIndex(-asset.Imports.Count);
            }

            var arr = e.Data.FirstOrDefault(p => S(p.Name) == "ChildSkills") as ArrayPropertyData;
            if (arr == null)
            {
                arr = new ArrayPropertyData(FName.FromString(asset, "ChildSkills"))
                { ArrayType = FName.FromString(asset, "ObjectProperty"), Value = Array.Empty<PropertyData>() };
                // insert at the schema-correct slot (ChildSkills sits before ValueOfXP in FWSkillDefinition)
                int at = e.Data.FindIndex(p => S(p.Name) == "ValueOfXP");
                if (at < 0) at = e.Data.FindIndex(p => S(p.Name) == "SkillEffects");
                if (at < 0) e.Data.Add(arr); else e.Data.Insert(at, arr);
                Console.WriteLine($"  (created ChildSkills array at data index {(at < 0 ? e.Data.Count - 1 : at)})");
            }

            var list = arr.Value.ToList();
            foreach (var spec in specs)
            {
                var parts = spec.Split('|');
                if (parts.Length != 2) { Console.WriteLine($"  bad spec (want 'pkg|obj'): {spec}"); return 1; }
                string pkgPath = parts[0], objName = parts[1];
                var pkgIdx = FindOrAddImport(coreU, "Package", new FPackageIndex(0), pkgPath);
                var objIdx = FindOrAddImport(classPkg, className, pkgIdx, objName);
                list.Add(new ObjectPropertyData(FName.FromString(asset, "ChildSkills")) { Value = objIdx });
                Console.WriteLine($"  + add {objName}  (obj fpi={objIdx.Index}, pkg fpi={pkgIdx.Index})");
            }
            arr.Value = list.ToArray();
            Console.WriteLine($"[{S(e.ObjectName)}] ChildSkills -> {arr.Value.Length}");
            asset.Write(outPath);
            Console.WriteLine($"wrote {outPath}");
            return 0;
        }

        Console.WriteLine("unknown mode: " + mode);
        return 1;
    }
}
