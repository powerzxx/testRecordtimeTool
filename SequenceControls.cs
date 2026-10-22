using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public static class RecorderForeground {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    public static bool BelongsTo(IntPtr owner) {
        IntPtr foreground = GetForegroundWindow();
        return foreground != IntPtr.Zero && GetAncestor(foreground, 3) == owner;
    }
}

// Native key repeat flags keep a held space from recording multiple steps.
public sealed class RecorderSpaceFilter : IMessageFilter {
    public Form Owner;
    public Control NameInput;
    public event EventHandler SpacePressed;
    public event EventHandler ExceptionPressed;
    public event EventHandler UndoPressed;
    public event EventHandler InteractionReceived;
    private void ReturnToTest() {
        // Focus the form itself, not an action button that Enter could activate.
        Owner.ActiveControl = null;
        Owner.Focus();
    }
    public bool PreFilterMessage(ref Message message) {
        if (Owner == null || !Owner.Enabled) return false;
        Control focus = Control.FromHandle(message.HWnd);
        if (focus == null || focus.FindForm() != Owner) return false;
        if ((message.Msg == 0x201 || message.Msg == 0xA1 || message.Msg == 0x100) && InteractionReceived != null)
            InteractionReceived(this, EventArgs.Empty);
        bool keyMessage = message.Msg == 0x100 || message.Msg == 0x101;
        bool firstPress = message.Msg == 0x100 && (message.LParam.ToInt64() & 0x40000000L) == 0;
        if (keyMessage && message.WParam.ToInt32() == (int)Keys.F8 && Control.ModifierKeys == Keys.None) {
            if (firstPress && ExceptionPressed != null) ExceptionPressed(this, EventArgs.Empty);
            return true;
        }
        if (keyMessage && message.WParam.ToInt32() == (int)Keys.Z && Control.ModifierKeys == Keys.Control && !(focus is TextBoxBase)) {
            if (firstPress && UndoPressed != null) UndoPressed(this, EventArgs.Empty);
            return true;
        }
        if (message.Msg == 0x201 &&
            (focus is Panel || focus is Label || focus is GroupBox ||
             focus is Form || focus is SplitContainer || focus is Splitter)) {
            ReturnToTest();
            return false; // Keep scrolling, splitter dragging and ordinary clicks working.
        }
        if ((message.Msg == 0x100 || message.Msg == 0x101) &&
            message.WParam.ToInt32() == (int)Keys.Escape && Control.ModifierKeys == Keys.None &&
            (!(focus is TextBoxBase) || focus == NameInput)) {
            ReturnToTest();
            return true;
        }
        if ((message.Msg != 0x100 && message.Msg != 0x101) ||
            message.WParam.ToInt32() != (int)Keys.Space) return false;
        if (focus is TextBoxBase || focus is ComboBox || focus is ListBox || focus is ToolStrip || Control.ModifierKeys != Keys.None) return false;
        if (message.Msg == 0x100 && (message.LParam.ToInt64() & 0x40000000L) == 0) {
            if (SpacePressed != null) SpacePressed(this, EventArgs.Empty);
        }
        return true;
    }
}

public sealed class RecorderDragButton : Button {
    private Point start;
    private bool dragging;
    private bool pressed;
    protected override void OnMouseDown(MouseEventArgs e) {
        dragging = false;
        pressed = e.Button == MouseButtons.Left;
        start = e.Location;
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        base.OnMouseMove(e);
        Size size = SystemInformation.DragSize;
        Rectangle threshold = new Rectangle(start.X - size.Width / 2,
            start.Y - size.Height / 2, size.Width, size.Height);
        if (pressed && !dragging && e.Button == MouseButtons.Left && !threshold.Contains(e.Location)) {
            dragging = true;
            pressed = false;
            DoDragDrop(new DataObject("RecorderStep", this), DragDropEffects.Copy | DragDropEffects.Move);
        }
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false;
        base.OnMouseUp(e);
    }
    protected override void OnClick(EventArgs e) {
        if (!dragging) base.OnClick(e);
    }
}
