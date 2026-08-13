#!/usr/bin/env python3
"""Report attributes and callbacks the Cocoa driver does not actually register.

Grepping the driver for iupClassRegisterAttribute is misleading in both directions: the
Cocoa backend began as a port of the GTK driver with large parts wrapped in #if 0, so a
plain grep counts registrations that the preprocessor throws away. Twice in this backend the
ONLY registration of an attribute was inside such a block -- IupDialog's BGCOLOR, and
IupText's TABSIZE/PADDING/OVERWRITE -- and each looked present until the blocks were removed.

So: strip #if 0 regions (honouring nesting) from both drivers, then diff what is left
against the GTK driver, which is the parity target.

    usage: audit_disabled.py [--all]     (default: only controls with findings)
"""

COMMON = set()

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'src')

# cocoa file -> gtk file. Only controls where both drivers implement the same class.
PAIRS = [
    ('iupcocoa_button.m',      'iupgtk_button.c'),
    ('iupcocoa_canvas.m',      'iupgtk_canvas.c'),
    ('iupcocoa_dialog.m',      'iupgtk_dialog.c'),
    ('iupcocoa_frame.m',       'iupgtk_frame.c'),
    ('iupcocoa_label.m',       'iupgtk_label.c'),
    ('iupcocoa_list.m',        'iupgtk_list.c'),
    ('iupcocoa_menu.m',        'iupgtk_menu.c'),
    ('iupcocoa_progressbar.m', 'iupgtk_progressbar.c'),
    ('iupcocoa_tabs.m',        'iupgtk_tabs.c'),
    ('iupcocoa_text.m',        'iupgtk_text.c'),
    ('iupcocoa_toggle.m',      'iupgtk_toggle.c'),
    ('iupcocoa_tree.m',        'iupgtk_tree.c'),
    ('iupcocoa_val.m',         'iupgtk_val.c'),
]

# Attributes that mean nothing on this platform: they exist to hand out X11/Windows handles.
PLATFORM_SPECIFIC = {
    'XDISPLAY', 'XWINDOW', 'XSCREEN', 'XSERVERVERSION',
    'HWND', 'HDC', 'HINSTANCE', 'WID',
}

# Deliberate decisions, with the reason. Listed rather than silently dropped so the choice
# stays visible and can be revisited.
ACKNOWLEDGED = {
    'IMINACTIVE': 'IUP documents it as GTK/Motif only; the Cocoa label handles the inactive '
                  'case by generating the image instead',
    'MAXIMIZED': 'reachable through PLACEMENT=MAXIMIZED, which is how the Cocoa dialog '
                 'implements it',
}

REGISTER = re.compile(
    r'iupClassRegister(?:Attribute|Callback)(?:Id2?)?\s*\(\s*ic\s*,\s*"([A-Z_0-9]+)"\s*,\s*([^;]*?)\)\s*;',
    re.S)


def strip_if0(path):
    """Remove regions the preprocessor discards, tracking nested conditionals.

    That means #if 0, and also #if MACRO where the file defines MACRO as 0 -- which is not a
    hypothetical: IupTabs gates TABTIP behind "#define IUPCOCOA_ENABLE_TABTIP 0", so the
    registration is compiled out while looking perfectly live. Missing that made this script
    report TABTIP as implemented when setting it did nothing at all.
    """
    if not os.path.exists(path):
        return None

    text = open(path, errors='replace').read()
    zero_macros = set(re.findall(r'^\s*#\s*define\s+([A-Za-z_]\w*)\s+0\s*$', text, re.M))

    def is_false(stripped):
        if re.match(r'#\s*if\s+0\b', stripped):
            return True
        m = re.match(r'#\s*if\s+([A-Za-z_]\w*)\s*$', stripped)
        return bool(m) and m.group(1) in zero_macros

    out, depth = [], 0
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if depth:
            if re.match(r'#\s*if', stripped):
                depth += 1
            elif re.match(r'#\s*endif', stripped):
                depth -= 1
            continue
        if is_false(stripped):
            depth = 1
            continue
        out.append(line)
    return ''.join(out)


def common_registrations():
    """Attributes every native control gets from iupBaseRegisterCommonAttrib.

    GTK re-registers several of these per control (FONT via gtkButtonSetFontAttrib, and so
    on) purely to specialise them. The Cocoa driver leaning on the shared registration is not
    a gap, so these must not be reported as absent."""
    text = strip_if0(os.path.join(SRC, 'iup_classbase.c'))
    return {m.group(1) for m in REGISTER.finditer(text or '')}


def registrations(path):
    text = strip_if0(path)
    if text is None:
        return None
    return {m.group(1): m.group(2) for m in REGISTER.finditer(text)}


def dead_only(cocoa_path, live):
    """Names that appear ONLY inside a removed #if 0 block -- the dangerous case."""
    whole = open(cocoa_path, errors='replace').read()
    everything = {m.group(1) for m in REGISTER.finditer(whole)}
    return sorted(everything - set(live))


def main():
    show_all = '--all' in sys.argv
    findings = 0
    global COMMON
    COMMON = common_registrations()

    for cocoa_name, gtk_name in PAIRS:
        cocoa_path = os.path.join(SRC, 'cocoa', cocoa_name)
        gtk_path = os.path.join(SRC, 'gtk', gtk_name)

        cocoa = registrations(cocoa_path)
        gtk = registrations(gtk_path)
        if cocoa is None or gtk is None:
            print('%-24s SKIP (no counterpart)' % cocoa_name)
            continue

        # In GTK but not live here. Ignore the ones GTK itself marks unsupported: matching
        # its "registered but does nothing" is parity, not a gap.
        missing = sorted(n for n in set(gtk) - set(cocoa)
                         if 'IUPAF_NOT_SUPPORTED' not in gtk[n]
                         and n not in COMMON
                         and n not in PLATFORM_SPECIFIC
                         and n not in ACKNOWLEDGED)
        # Registered here with no getter AND no setter, where GTK has a real handler.
        # NULL/NULL here where GTK has a real handler. Cocoa's own IUPAF_NOT_SUPPORTED does
        # not count: that flag is the documented way to say "known, deliberately absent", so
        # reporting it would be reporting an honest declaration as a defect.
        inert = sorted(n for n, v in cocoa.items()
                       if re.match(r'\s*NULL\s*,\s*NULL', v)
                       and n in gtk
                       and not re.match(r'\s*NULL\s*,\s*NULL', gtk[n])
                       and 'IUPAF_NOT_SUPPORTED' not in gtk[n]
                       and 'IUPAF_NOT_SUPPORTED' not in v
                       and n not in PLATFORM_SPECIFIC
                       and n not in ACKNOWLEDGED)
        buried = [n for n in dead_only(cocoa_path, cocoa)
                  if n in gtk and n not in PLATFORM_SPECIFIC and n not in ACKNOWLEDGED]

        if not (missing or inert or buried) and not show_all:
            continue
        findings += len(missing) + len(inert) + len(buried)

        print('== %s  (live: %d, gtk: %d)' % (cocoa_name, len(cocoa), len(gtk)))
        if buried:
            print('   compiled out     : %s' % ' '.join(buried))
        if missing:
            print('   absent            : %s' % ' '.join(missing))
        if inert:
            print('   NULL/NULL here    : %s' % ' '.join(inert))

    if ACKNOWLEDGED:
        print('\nDeliberately not reported:')
        for name in sorted(ACKNOWLEDGED):
            print('   %-14s %s' % (name, ACKNOWLEDGED[name]))

    print('\n%d finding(s).' % findings)
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
