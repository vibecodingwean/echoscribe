"""GTK overlay and toast windows."""

from __future__ import annotations

import logging
import math
import threading
import time
from pathlib import Path

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402


LOG = logging.getLogger(__name__)


class Overlay:
    def __init__(
        self,
        icon_path: Path,
        icon_size: int = 58,
        margin: int = 24,
        top: int = 72,
        toast_ms: int = 1800,
    ) -> None:
        self.icon_path = icon_path
        self.icon_size = icon_size
        self.margin = margin
        self.top = top
        self.toast_ms = toast_ms
        self.badge_width = 410
        self.badge_height = max(76, icon_size + 20)
        self.logo_visible_width = icon_size + 24
        self.badge_window = self._make_window()
        self.toast_label = Gtk.Label()
        self.toast_label.set_xalign(0.0)
        self.toast_label.set_single_line_mode(True)
        self.toast_label.set_ellipsize(Pango.EllipsizeMode.END)
        self._toast_timeout: int | None = None
        self._animation_timeout: int | None = None
        self._visible = False
        self._collapsed = False
        self._install_css()
        self._build_badge()

    def show_recording(self) -> None:
        GLib.idle_add(self._show_badge, "Recording...", True)

    def show_processing(self, text: str) -> None:
        GLib.idle_add(self._show_badge, text, True)

    def hide_icon(self) -> None:
        GLib.idle_add(self._hide_badge)

    def show_toast(self, text: str) -> None:
        GLib.idle_add(self._show_badge, text, False)

    def set_clipboard_text(self, text: str, timeout: float = 2.0) -> bool:
        done = threading.Event()
        result = {"ok": False}

        def set_clipboard() -> bool:
            try:
                clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
                clipboard.set_text(text, -1)
                clipboard.store()
                result["ok"] = True
            except Exception as exc:
                LOG.debug("GTK clipboard failed: %s", exc)
            finally:
                done.set()
            return False

        GLib.idle_add(set_clipboard)
        done.wait(timeout)
        return result["ok"]

    def run(self) -> None:
        Gtk.main()

    def stop(self) -> None:
        GLib.idle_add(Gtk.main_quit)

    def _make_window(self) -> Gtk.Window:
        window = Gtk.Window(type=Gtk.WindowType.POPUP)
        screen = Gdk.Screen.get_default()
        if screen is not None:
            visual = screen.get_rgba_visual()
            if visual is not None:
                window.set_visual(visual)
        window.set_decorated(False)
        window.set_keep_above(True)
        window.set_accept_focus(False)
        window.set_skip_taskbar_hint(True)
        window.set_skip_pager_hint(True)
        window.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)
        window.set_app_paintable(True)
        return window

    def _install_css(self) -> None:
        provider = Gtk.CssProvider()
        provider.load_from_data(
            b"""
            .echoscribe-icon {
              background: transparent;
            }
            .echoscribe-badge {
              background: transparent;
              color: #111827;
            }
            .echoscribe-badge-label {
              color: #0f172a;
              font: 700 16px Sans;
            }
            """
        )
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.add_provider_for_screen(
                screen,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    def _build_icon(self) -> Gtk.Widget:
        icon = Gtk.DrawingArea()
        icon.get_style_context().add_class("echoscribe-icon")
        icon.set_size_request(self.icon_size, self.icon_size)
        icon.connect("draw", self._draw_microphone_icon)
        return icon

    def _build_badge(self) -> None:
        self.badge_window.set_default_size(self.badge_width, self.badge_height)
        box = Gtk.DrawingArea()
        box.get_style_context().add_class("echoscribe-badge")
        box.set_size_request(self.badge_width, self.badge_height)
        box.connect("draw", self._draw_badge_background)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_valign(Gtk.Align.CENTER)
        row.set_margin_start(14)
        row.set_margin_end(22)
        row.set_margin_top(9)
        row.set_margin_bottom(9)
        row.set_size_request(self.badge_width - 36, self.badge_height - 18)
        row.pack_start(self._build_icon(), False, False, 0)
        self.toast_label.set_max_width_chars(42)
        self.toast_label.set_size_request(self.badge_width - self.icon_size - 68, -1)
        self.toast_label.set_hexpand(False)
        self.toast_label.get_style_context().add_class("echoscribe-badge-label")
        row.pack_start(self.toast_label, False, False, 0)
        overlay = Gtk.Overlay()
        overlay.set_size_request(self.badge_width, self.badge_height)
        overlay.add(box)
        overlay.add_overlay(row)
        self.badge_window.add(overlay)

    def _draw_badge_background(self, widget: Gtk.Widget, cr: object) -> bool:
        width = widget.get_allocated_width()
        height = widget.get_allocated_height()
        radius = height / 2 - 1

        # Soft shadow.
        cr.save()
        cr.translate(0, 3)
        self._rounded_rect(cr, 4, 4, width - 8, height - 8, radius)
        cr.set_source_rgba(0.05, 0.09, 0.18, 0.18)
        cr.fill()
        cr.restore()

        # Liquid glass body.
        self._rounded_rect(cr, 1, 1, width - 2, height - 4, radius)
        gradient = self._linear_gradient(0, 0, 0, height)
        gradient.add_color_stop_rgba(0.0, 1.0, 1.0, 1.0, 0.94)
        gradient.add_color_stop_rgba(0.45, 0.94, 0.97, 1.0, 0.86)
        gradient.add_color_stop_rgba(1.0, 0.86, 0.92, 1.0, 0.78)
        cr.set_source(gradient)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.86)
        cr.set_line_width(1.2)
        cr.stroke()

        # Top specular highlight.
        self._rounded_rect(cr, 10, 8, width - 20, height * 0.44, radius * 0.75)
        shine = self._linear_gradient(0, 8, 0, height * 0.48)
        shine.add_color_stop_rgba(0, 1, 1, 1, 0.46)
        shine.add_color_stop_rgba(1, 1, 1, 1, 0.08)
        cr.set_source(shine)
        cr.fill()
        return False

    def _draw_microphone_icon(self, widget: Gtk.Widget, cr: object) -> bool:
        size = min(widget.get_allocated_width(), widget.get_allocated_height())
        cx = size / 2
        cy = size / 2

        # Blue glossy orb.
        cr.arc(cx, cy, size * 0.46, 0, math.tau)
        orb = self._linear_gradient(0, 0, 0, size)
        orb.add_color_stop_rgba(0, 0.42, 0.78, 1.0, 1)
        orb.add_color_stop_rgba(0.55, 0.07, 0.42, 1.0, 1)
        orb.add_color_stop_rgba(1, 0.02, 0.22, 0.78, 1)
        cr.set_source(orb)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.42)
        cr.set_line_width(1.1)
        cr.stroke()

        cr.arc(cx - size * 0.13, cy - size * 0.17, size * 0.16, 0, math.tau)
        highlight = self._linear_gradient(0, cy - size * 0.34, 0, cy)
        highlight.add_color_stop_rgba(0, 1, 1, 1, 0.58)
        highlight.add_color_stop_rgba(1, 1, 1, 1, 0.0)
        cr.set_source(highlight)
        cr.fill()

        # White microphone glyph.
        cr.set_source_rgba(1, 1, 1, 0.96)
        self._rounded_rect(cr, cx - size * 0.105, cy - size * 0.25, size * 0.21, size * 0.38, size * 0.105)
        cr.fill()

        cr.set_line_cap(1)
        cr.set_line_width(size * 0.055)
        cr.arc(cx, cy - size * 0.03, size * 0.22, 0, math.pi)
        cr.stroke()
        cr.move_to(cx, cy + size * 0.19)
        cr.line_to(cx, cy + size * 0.31)
        cr.stroke()
        cr.move_to(cx - size * 0.14, cy + size * 0.31)
        cr.line_to(cx + size * 0.14, cy + size * 0.31)
        cr.stroke()
        return False

    def _linear_gradient(self, x0: float, y0: float, x1: float, y1: float) -> cairo.LinearGradient:
        return cairo.LinearGradient(x0, y0, x1, y1)

    def _rounded_rect(self, cr: object, x: float, y: float, width: float, height: float, radius: float) -> None:
        radius = min(radius, width / 2, height / 2)
        cr.new_sub_path()
        cr.arc(x + width - radius, y + radius, radius, -math.pi / 2, 0)
        cr.arc(x + width - radius, y + height - radius, radius, 0, math.pi / 2)
        cr.arc(x + radius, y + height - radius, radius, math.pi / 2, math.pi)
        cr.arc(x + radius, y + radius, radius, math.pi, math.pi * 1.5)
        cr.close_path()

    def _show_badge(self, text: str, keep_logo: bool) -> bool:
        if self._toast_timeout is not None:
            GLib.source_remove(self._toast_timeout)
            self._toast_timeout = None
        if self._animation_timeout is not None:
            GLib.source_remove(self._animation_timeout)
            self._animation_timeout = None
        self.toast_label.set_text(text[:180])
        self.badge_window.show_all()
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        y = self.top
        start_x = self._current_x(default=self._hidden_x())
        if not self._visible:
            start_x = self._hidden_x()
        end_x = self._expanded_x()
        self.badge_window.move(start_x, y)
        self._visible = True
        self._collapsed = False
        self._animate_window(self.badge_window, start_x, end_x, y, 210)

        def settle_later() -> bool:
            if keep_logo:
                self._collapse_badge()
            else:
                self._hide_badge()
            self._toast_timeout = None
            return False

        self._toast_timeout = GLib.timeout_add(self.toast_ms, settle_later)
        return False

    def _collapse_badge(self) -> bool:
        if not self._visible:
            return False
        if self._animation_timeout is not None:
            GLib.source_remove(self._animation_timeout)
            self._animation_timeout = None
        y = self.top
        self._animate_window(self.badge_window, self._current_x(default=self._expanded_x()), self._collapsed_x(), y, 180)
        self._collapsed = True
        return False

    def _hide_badge(self) -> bool:
        if self._toast_timeout is not None:
            GLib.source_remove(self._toast_timeout)
            self._toast_timeout = None
        if not self._visible:
            self.badge_window.hide()
            return False
        y = self.top
        self._animate_window(
            self.badge_window,
            self._current_x(default=self._collapsed_x()),
            self._hidden_x(),
            y,
            180,
            hide=True,
        )
        self._visible = False
        self._collapsed = False
        return False

    def _animate_window(
        self,
        window: Gtk.Window,
        start_x: int,
        end_x: int,
        y: int,
        duration_ms: int,
        hide: bool = False,
    ) -> None:
        started = time.monotonic()

        def tick() -> bool:
            elapsed = (time.monotonic() - started) * 1000
            progress = min(1.0, elapsed / max(duration_ms, 1))
            eased = 1 - (1 - progress) * (1 - progress)
            x = int(start_x + (end_x - start_x) * eased)
            window.move(x, y)
            if progress >= 1:
                if hide:
                    window.hide()
                self._animation_timeout = None
                return False
            return True

        self._animation_timeout = GLib.timeout_add(16, tick)

    def _screen_width(self) -> int:
        screen = Gdk.Screen.get_default()
        if screen is None:
            return 1200
        return screen.get_width()

    def _expanded_x(self) -> int:
        return max(self.margin, self._screen_width() - self.badge_width - self.margin)

    def _collapsed_x(self) -> int:
        return self._screen_width() - self.logo_visible_width

    def _hidden_x(self) -> int:
        return self._screen_width() + 4

    def _current_x(self, default: int) -> int:
        if not self._visible:
            return default
        try:
            x, _ = self.badge_window.get_position()
            return x
        except Exception:
            return default

