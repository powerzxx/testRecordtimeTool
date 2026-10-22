using System;
using System.IO;
using System.Runtime.InteropServices;

namespace RecorderRecycle {
    // IFileOperation provides the actual recycled item in PostDeleteItem. A
    // successful delete alone is insufficient: it might have been permanent.
    public static class Backup {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingName(string path, IntPtr context, ref Guid iid, out IShellItem item);

        public static string MoveToRecycleBin(string path, IntPtr owner) {
            path = Path.GetFullPath(path);
            if (!File.Exists(path)) throw new FileNotFoundException("Backup file does not exist", path);
            IFileOperation operation = null;
            IShellItem source = null;
            try {
                Guid iid = typeof(IShellItem).GUID;
                Marshal.ThrowExceptionForHR(SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out source));
                operation = (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("3AD05575-8857-4850-9277-11B85BDB8E09")));
                operation.SetOwnerWindow(owner);
                // Recycle on delete, fail immediately on error, no extra UI or
                // connected-file deletion, and retain Explorer undo information.
                operation.SetOperationFlags(0x00080000 | 0x00100000 | 0x0400 | 0x0010 | 0x0004 | 0x2000 | 0x0040);
                var sink = new RecycleSink();
                operation.DeleteItem(source, sink);
                operation.PerformOperations();
                bool aborted;
                operation.GetAnyOperationsAborted(out aborted);
                if (sink.Result < 0) Marshal.ThrowExceptionForHR(sink.Result);
                if (aborted || !sink.Completed || String.IsNullOrEmpty(sink.RecycledPath) || !File.Exists(sink.RecycledPath) || File.Exists(path))
                    throw new IOException("The backup could not be confirmed in the Windows Recycle Bin. The original log must not be cleared.");
                return sink.RecycledPath;
            }
            finally {
                if (source != null) Marshal.ReleaseComObject(source);
                if (operation != null) Marshal.ReleaseComObject(operation);
            }
        }
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class RecycleSink : IFileOperationProgressSink {
        public bool Completed;
        public int Result;
        public string RecycledPath;
        public int StartOperations() { return 0; }
        public int FinishOperations(int result) { return 0; }
        public int PreRenameItem(uint flags, IShellItem item, string name) { return 0; }
        public int PostRenameItem(uint flags, IShellItem item, string name, int result, IShellItem created) { return 0; }
        public int PreMoveItem(uint flags, IShellItem item, IShellItem destination, string name) { return 0; }
        public int PostMoveItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem created) { return 0; }
        public int PreCopyItem(uint flags, IShellItem item, IShellItem destination, string name) { return 0; }
        public int PostCopyItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem created) { return 0; }
        public int PreDeleteItem(uint flags, IShellItem item) { return 0; }
        public int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem recycled) {
            Completed = true;
            Result = result;
            if (result >= 0 && recycled != null) {
                IntPtr displayName = IntPtr.Zero;
                try {
                    recycled.GetDisplayName(0x80058000, out displayName); // SIGDN_FILESYSPATH
                    RecycledPath = Marshal.PtrToStringUni(displayName);
                }
                catch { RecycledPath = null; }
                finally { if (displayName != IntPtr.Zero) Marshal.FreeCoTaskMem(displayName); }
            }
            return 0;
        }
        public int PreNewItem(uint flags, IShellItem destination, string name) { return 0; }
        public int PostNewItem(uint flags, IShellItem destination, string name, string template, uint attributes, int result, IShellItem created) { return 0; }
        public int UpdateProgress(uint total, uint complete) { return 0; }
        public int ResetTimer() { return 0; }
        public int PauseTimer() { return 0; }
        public int ResumeTimer() { return 0; }
    }

    [ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileOperation {
        void Advise(IFileOperationProgressSink sink, out uint cookie);
        void Unadvise(uint cookie);
        void SetOperationFlags(uint flags);
        void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(IntPtr dialog);
        void SetProperties(IntPtr properties);
        void SetOwnerWindow(IntPtr owner);
        void ApplyPropertiesToItem(IShellItem item);
        void ApplyPropertiesToItems([MarshalAs(UnmanagedType.IUnknown)] object items);
        void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
        void RenameItems([MarshalAs(UnmanagedType.IUnknown)] object items, [MarshalAs(UnmanagedType.LPWStr)] string name);
        void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
        void MoveItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
        void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
        void CopyItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
        void DeleteItem(IShellItem item, IFileOperationProgressSink sink);
        void DeleteItems([MarshalAs(UnmanagedType.IUnknown)] object items);
        void NewItem(IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, IFileOperationProgressSink sink);
        void PerformOperations();
        void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem {
        void BindToHandler(IntPtr context, ref Guid handler, ref Guid iid, out IntPtr result);
        void GetParent(out IShellItem parent);
        void GetDisplayName(uint nameType, out IntPtr name);
        void GetAttributes(uint mask, out uint attributes);
        void Compare(IShellItem other, uint hint, out int order);
    }

    [ComVisible(true), Guid("04B0F1A7-9490-44BC-96E1-4296A31252E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileOperationProgressSink {
        [PreserveSig] int StartOperations();
        [PreserveSig] int FinishOperations(int result);
        [PreserveSig] int PreRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
        [PreserveSig] int PreMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
        [PreserveSig] int PreCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
        [PreserveSig] int PreDeleteItem(uint flags, IShellItem item);
        [PreserveSig] int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem recycled);
        [PreserveSig] int PreNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, uint attributes, int result, IShellItem created);
        [PreserveSig] int UpdateProgress(uint total, uint complete);
        [PreserveSig] int ResetTimer();
        [PreserveSig] int PauseTimer();
        [PreserveSig] int ResumeTimer();
    }
}
