using System;
using System.IO;
using System.Linq;
using Mono.Cecil;

// Apply the small offline/controller fixes required by the NextOS loader
// without rewriting assembly metadata. Rewriting the DLL would disturb the
// Xamarin assembly-store/AOT identity, so this changes only existing IL bytes
// in-place and leaves every RVA/token/MVID untouched.
internal static class PatchStardewOsk
{
    private static int RvaToFileOffset(byte[] image, int rva)
    {
        int pe = BitConverter.ToInt32(image, 0x3c);
        int sections = BitConverter.ToUInt16(image, pe + 6);
        int optionalSize = BitConverter.ToUInt16(image, pe + 20);
        int section = pe + 24 + optionalSize;

        for (int i = 0; i < sections; i++, section += 40)
        {
            int virtualSize = BitConverter.ToInt32(image, section + 8);
            int virtualAddress = BitConverter.ToInt32(image, section + 12);
            int rawSize = BitConverter.ToInt32(image, section + 16);
            int rawOffset = BitConverter.ToInt32(image, section + 20);
            int span = Math.Max(virtualSize, rawSize);
            if (rva >= virtualAddress && rva < virtualAddress + span)
                return rawOffset + (rva - virtualAddress);
        }

        throw new InvalidOperationException("method RVA is outside PE sections");
    }

    private static int MethodCodeOffset(byte[] image, int methodOffset, out int codeSize)
    {
        byte first = image[methodOffset];
        if ((first & 3) == 2)
        {
            codeSize = first >> 2;
            return methodOffset + 1;
        }

        if ((first & 3) != 3)
            throw new InvalidOperationException("unsupported managed method header");

        ushort flagsAndSize = BitConverter.ToUInt16(image, methodOffset);
        int headerSize = ((flagsAndSize >> 12) & 0xf) * 4;
        codeSize = BitConverter.ToInt32(image, methodOffset + 4);
        return methodOffset + headerSize;
    }

    private static int GetCodeOffset(byte[] image, MethodDefinition method,
                                     out int codeSize)
    {
        int methodOffset = RvaToFileOffset(image, method.RVA);
        int codeOffset = MethodCodeOffset(image, methodOffset, out codeSize);
        if (!method.HasBody || codeSize != method.Body.CodeSize)
            throw new InvalidOperationException(method.FullName + " code size mismatch");
        return codeOffset;
    }

    private static void ReplaceBodyWithTrue(byte[] image, MethodDefinition method)
    {
        if (method.Body.HasExceptionHandlers)
            throw new InvalidOperationException(method.FullName + " has exception handlers");
        int codeSize;
        int codeOffset = GetCodeOffset(image, method, out codeSize);
        if (codeSize < 2)
            throw new InvalidOperationException(method.FullName + " body is too short");
        Array.Clear(image, codeOffset, codeSize);
        image[codeOffset] = 0x17;     // ldc.i4.1
        image[codeOffset + 1] = 0x2a; // ret
    }

    public static int Main(string[] args)
    {
        if (args.Length != 2)
        {
            Console.Error.WriteLine("usage: PatchStardewOsk <input.dll> <output.dll>");
            return 2;
        }

        AssemblyDefinition assembly = AssemblyDefinition.ReadAssembly(args[0]);
        ModuleDefinition module = assembly.MainModule;
        TypeDefinition textBox = module.GetType("StardewValley.Menus.TextBox");
        TypeDefinition game1 = module.GetType("StardewValley.Game1");
        TypeDefinition newDaySync = module.GetType("StardewValley.NewDaySynchronizer");
        MethodDefinition androidKeyboard = textBox.Methods.Single(method =>
            method.Name == "ShowAndroidKeyboard" && method.Parameters.Count == 0);
        MethodDefinition showTextEntry = game1.Methods.Single(method =>
            method.Name == "showTextEntry" && method.Parameters.Count == 1 &&
            method.Parameters[0].ParameterType.FullName == textBox.FullName);
        MethodDefinition readyForSave = newDaySync.Methods.Single(method =>
            method.Name == "readyForSave" && method.Parameters.Count == 0);

        if (!androidKeyboard.HasBody || androidKeyboard.Body.HasExceptionHandlers)
            throw new InvalidOperationException("unexpected ShowAndroidKeyboard body");

        byte[] image = File.ReadAllBytes(args[0]);
        int diskCodeSize;
        int codeOffset = GetCodeOffset(image, androidKeyboard, out diskCodeSize);
        if (diskCodeSize < 7)
            throw new InvalidOperationException("ShowAndroidKeyboard code size mismatch");

        // ldarg.0; call Game1.showTextEntry(TextBox); ret; nop ...
        Array.Clear(image, codeOffset, diskCodeSize);
        image[codeOffset] = 0x02;
        image[codeOffset + 1] = 0x28;
        byte[] token = BitConverter.GetBytes(showTextEntry.MetadataToken.ToInt32());
        Buffer.BlockCopy(token, 0, image, codeOffset + 2, token.Length);
        image[codeOffset + 6] = 0x2a;

        // This Android build can wait forever in the network ready barrier on
        // an offline first save. NextOS has no online multiplayer backend, so
        // the offline port can acknowledge that barrier immediately.
        ReplaceBodyWithTrue(image, readyForSave);

        File.WriteAllBytes(args[1], image);
        Console.WriteLine(
            "patched OSK RVA 0x{0:x} and offline save barrier RVA 0x{1:x}",
            androidKeyboard.RVA, readyForSave.RVA);
        return 0;
    }
}
