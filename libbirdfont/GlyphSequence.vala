/*
    Copyright (C) 2013 Johan Mattsson

    This library is free software; you can redistribute it and/or modify 
    it under the terms of the GNU Lesser General Public License as 
    published by the Free Software Foundation; either version 3 of the 
    License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful, but 
    WITHOUT ANY WARRANTY; without even the implied warranty of 
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
    Lesser General Public License for more details.
*/
namespace BirdFont {

public class GlyphSequence {
	
	/** A list of all glyphs */
	public Gee.ArrayList<Glyph?> glyph;

	/** A list of corresponding glyph ranges if applicable. */ 
	public Gee.ArrayList<GlyphRange?> ranges;

	public GlyphSequence () {
		glyph = new Gee.ArrayList<Glyph?> ();
		ranges = new Gee.ArrayList<GlyphRange?> ();
	}
	
	/** Do ligature substitution.
	 * @return a new sequence with ligatures
	 */
	public GlyphSequence process_ligatures () {
		// FIXME add range to ligature
		GlyphSequence ligatures = new GlyphSequence ();
		Font font = BirdFont.get_current_font ();
		Glyph liga;
		GlyphCollection? gc;
		bool has_range = false;
		
		foreach (Glyph? g in glyph) {
			ligatures.glyph.add (g);
		}
				
		foreach (GlyphRange? r in ranges) { 
			ligatures.ranges.add (r);
			if (r != null) {
				has_range = true;
			}
		}
		
		// FIXME: ligatures make this list invalid
		// skip ligature substitution if this sequence contains ranges
		if (has_range) {
			return ligatures;
		}
		
			
		for (uint i = 0; ; i++) {
			gc = font.get_ligature (i);
			
			if (gc == null) {
				break;
			}

			liga = ((!) gc).get_current ();		
			ligatures.replace (liga.get_ligature (), liga);
			i++;
		}
		
		return ligatures;
	}
	
	void replace (GlyphSequence old, Glyph replacement) {
		int i = 0;
		while (i < glyph.size) {
			if (starts_with (old, i)) {
				substitute (i, old.glyph.size, replacement);
				i = 0;
			} else {
				i++;
			}
		}
	}
	
	bool starts_with (GlyphSequence old, uint index) {
		Glyph? gl;

		foreach (Glyph? g in old.glyph) {
			if (index >= glyph.size) {
				return false;
			}
			
			gl = glyph.get ((int) index);
		
			if (g != gl) {
				return false;
			}
			
			index++;
		}
		
		return true;
	}
	
	void substitute (uint index, uint length, Glyph substitute) {
		Gee.ArrayList<Glyph?> new_list = new Gee.ArrayList<Glyph?> ();
		int i = 0;
		
		foreach (Glyph? g in glyph) {
			if (i == index) {
				new_list.add (substitute);
			}

			if (!(i >= index && i < index + length)) {
				new_list.add (g);
			}

			i++;
		}
		
		glyph = new_list;
				
	}
}

}
