/*
    Copyright (C) 2012 Johan Mattsson

    This library is free software; you can redistribute it and/or modify 
    it under the terms of the GNU Lesser General Public License as 
    published by the Free Software Foundation; either version 3 of the 
    License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful, but 
    WITHOUT ANY WARRANTY; without even the implied warranty of 
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
    Lesser General Public License for more details.
*/

using Gdk;

namespace BirdFont {

// FIXME a lot of these things have been replaced and can safely be removed

public enum Key {
	NONE = 0,
	UP = 65362,
	RIGHT = 65363,
	DOWN = 65364,
	LEFT = 65361,
	PG_UP = 65365,
	PG_DOWN = 65366,
	ENTER = 65293,
	BACK_SPACE = 65288,
	SHIFT_LEFT = 65505,
	SHIFT_RIGHT = 65506,
	CTRL_LEFT = 65507,
	CTRL_RIGHT = 65508,
	CAPS_LOCK = 65509,
	ALT_LEFT = 65513,
	ALT_RIGHT = 65514,
	ALT_GR = 65027,
	LOGO_LEFT = 65515,
	LOGO_RIGHT = 65516,
	CONTEXT_MENU = 65383,
	TAB = 65289,
	DEL = 65535
}

bool is_arrow_key (uint keyval) {
	return keyval == Key.UP ||
		keyval == Key.DOWN ||
		keyval == Key.LEFT ||
		keyval == Key.RIGHT;
}

bool is_modifier_key (uint i) {
	return Key.UP == i ||
		Key.RIGHT == i ||
		Key.DOWN == i ||
		Key.LEFT == i ||
		Key.PG_UP == i ||
		Key.PG_DOWN == i ||
		Key.ENTER == i ||
		Key.BACK_SPACE == i ||
		Key.SHIFT_LEFT == i ||
		Key.SHIFT_RIGHT == i ||
		Key.CTRL_LEFT == i ||
		Key.CTRL_RIGHT == i ||
		Key.ALT_LEFT == i ||
		Key.ALT_RIGHT == i ||
		Key.ALT_GR == i || 
		Key.LOGO_LEFT == i || 
		Key.LOGO_RIGHT == i || 
		Key.TAB == i || 
		Key.CAPS_LOCK == i || 
		Key.LOGO_RIGHT == i;
}

/** Modifier flags */
public static const uint NONE  = 0;
public static const uint CTRL  = 1 << 0;
public static const uint ALT   = 1 << 2;
public static const uint SHIFT = 1 << 3;
public static const uint LOGO  = 1 << 4;

public class KeyBindings {
	
	static bool modifier_ctrl = false;
	static bool modifier_alt = false;
	static bool modifier_shift = false;
		
	public static uint modifier = 0;

	public static bool require_modifier;

	public static void reset () {
		modifier = NONE;
		modifier_ctrl = false;
		modifier_alt = false;
		modifier_shift = false;
	}

	public static void set_require_modifier (bool t) {
		require_modifier = t;
	}

	private static uint get_mod_from_key (uint keyval) {
		uint mod = 0;
		mod |= (keyval == Key.CTRL_RIGHT || keyval == Key.CTRL_LEFT) ? CTRL : 0;
		mod |= (keyval == Key.SHIFT_RIGHT || keyval == Key.SHIFT_LEFT) ? SHIFT : 0;
		mod |= (keyval == Key.ALT_LEFT || keyval == Key.ALT_GR) ? ALT : 0;
		return mod;		
	}

	public static void remove_modifier_from_keyval (uint keyval) {
		uint mod;
				
		mod = get_mod_from_key (keyval);
		set_modifier (modifier ^ mod);		
	}

	public static void add_modifier_from_keyval (uint keyval) {
		uint mod = get_mod_from_key (keyval);
		set_modifier (modifier | mod);
	}

	public static void set_modifier (uint mod) {
		modifier = mod;

		modifier_ctrl = ((modifier & CTRL) > 0);
		modifier_alt = ((modifier & ALT) > 0);
		modifier_shift = ((modifier & SHIFT) > 0);
	}

	public static bool has_alt () {
		return modifier_alt;
	}
	
	public static bool has_shift () {
		return modifier_shift;
	}
		
	public static bool has_ctrl () {
		return modifier_ctrl;
	}
}

}
