using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace BoltSnip
{
    internal static class BoltSnipMenuStyle
    {
        internal static readonly Color SurfaceColor = Color.FromArgb(250, 252, 253);
        internal static readonly Color TextColor = Color.FromArgb(32, 40, 45);
        internal static readonly Color MutedTextColor = Color.FromArgb(102, 116, 123);
        internal static readonly Color DividerColor = Color.FromArgb(223, 231, 234);
        internal static readonly Color AccentColor = Color.FromArgb(52, 190, 208);
        internal static readonly Color HoverColor = Color.FromArgb(230, 244, 247);

        internal static void Apply(ContextMenuStrip menu, Font font)
        {
            menu.AutoSize = true;
            menu.BackColor = SurfaceColor;
            menu.ForeColor = TextColor;
            menu.Font = font;
            menu.ImageScalingSize = new Size(18, 18);
            menu.MinimumSize = new Size(248, 0);
            menu.Renderer = new BoltSnipMenuRenderer();
            menu.ShowImageMargin = true;
            menu.ShowCheckMargin = false;
            menu.Padding = new Padding(2);
        }

        internal static void ApplyItem(ToolStripItem item)
        {
            item.AutoSize = true;
            item.ForeColor = TextColor;
            item.Margin = new Padding(0, 1, 0, 1);
            item.Padding = new Padding(5, 4, 8, 4);
        }

        internal static void ApplySeparator(ToolStripSeparator separator)
        {
            separator.Margin = new Padding(0, 5, 0, 5);
        }
    }

    internal sealed class BoltSnipMenuRenderer : ToolStripProfessionalRenderer
    {
        internal BoltSnipMenuRenderer()
            : base(new BoltSnipColorTable())
        {
            RoundedEdges = false;
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected && !e.Item.Pressed)
            {
                return;
            }

            Rectangle bounds = new Rectangle(3, 1, e.Item.Width - 6, e.Item.Height - 2);
            SmoothingMode previous = e.Graphics.SmoothingMode;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = RoundedRectangle(bounds, 7))
            using (Brush hover = new SolidBrush(BoltSnipMenuStyle.HoverColor))
            using (Brush accent = new SolidBrush(BoltSnipMenuStyle.AccentColor))
            {
                e.Graphics.FillPath(hover, path);
                Rectangle rail = new Rectangle(bounds.Left + 3, bounds.Top + 6, 3, Math.Max(6, bounds.Height - 12));
                using (GraphicsPath railPath = RoundedRectangle(rail, 2))
                {
                    e.Graphics.FillPath(accent, railPath);
                }
            }
            e.Graphics.SmoothingMode = previous;
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled
                ? BoltSnipMenuStyle.TextColor
                : BoltSnipMenuStyle.MutedTextColor;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            Rectangle box = new Rectangle(10, (e.Item.Height - 16) / 2, 16, 16);
            SmoothingMode previous = e.Graphics.SmoothingMode;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (Brush background = new SolidBrush(BoltSnipMenuStyle.AccentColor))
            using (GraphicsPath boxPath = RoundedRectangle(box, 5))
            using (Pen check = new Pen(Color.White, 2f))
            {
                check.StartCap = LineCap.Round;
                check.EndCap = LineCap.Round;
                e.Graphics.FillPath(background, boxPath);
                Point first = new Point(box.Left + 4, box.Top + 8);
                Point second = new Point(box.Left + 7, box.Top + 11);
                Point third = new Point(box.Left + 12, box.Top + 5);
                e.Graphics.DrawLines(check, new[] { first, second, third });
            }
            e.Graphics.SmoothingMode = previous;
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using (Pen divider = new Pen(BoltSnipMenuStyle.DividerColor))
            {
                e.Graphics.DrawLine(divider, 38, y, e.Item.Width - 10, y);
            }
        }

        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e)
        {
            using (Brush surface = new SolidBrush(BoltSnipMenuStyle.SurfaceColor))
            {
                e.Graphics.FillRectangle(surface, e.AffectedBounds);
            }
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            Rectangle border = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
            using (Pen outline = new Pen(BoltSnipMenuStyle.DividerColor))
            {
                e.Graphics.DrawRectangle(outline, border);
            }
        }

        private static GraphicsPath RoundedRectangle(Rectangle rectangle, int radius)
        {
            int diameter = Math.Min(radius * 2, Math.Min(rectangle.Width, rectangle.Height));
            GraphicsPath path = new GraphicsPath();
            if (diameter <= 0)
            {
                path.AddRectangle(rectangle);
                return path;
            }

            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private sealed class BoltSnipColorTable : ProfessionalColorTable
        {
            internal BoltSnipColorTable()
            {
                UseSystemColors = false;
            }

            public override Color ToolStripDropDownBackground { get { return BoltSnipMenuStyle.SurfaceColor; } }
            public override Color ImageMarginGradientBegin { get { return BoltSnipMenuStyle.SurfaceColor; } }
            public override Color ImageMarginGradientMiddle { get { return BoltSnipMenuStyle.SurfaceColor; } }
            public override Color ImageMarginGradientEnd { get { return BoltSnipMenuStyle.SurfaceColor; } }
            public override Color MenuBorder { get { return BoltSnipMenuStyle.DividerColor; } }
            public override Color MenuItemBorder { get { return BoltSnipMenuStyle.HoverColor; } }
            public override Color MenuItemSelected { get { return BoltSnipMenuStyle.HoverColor; } }
            public override Color MenuItemSelectedGradientBegin { get { return BoltSnipMenuStyle.HoverColor; } }
            public override Color MenuItemSelectedGradientEnd { get { return BoltSnipMenuStyle.HoverColor; } }
            public override Color SeparatorDark { get { return BoltSnipMenuStyle.DividerColor; } }
            public override Color SeparatorLight { get { return BoltSnipMenuStyle.SurfaceColor; } }
        }
    }
}
