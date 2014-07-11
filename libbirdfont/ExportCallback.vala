/*
    Copyright (C) 2014 Johan Mattsson

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

public class ExportCallback : GLib.Object {
	
	public signal void file_exported ();
	
	public ExportCallback () {
	}

	public void export_fonts_in_background () {
		Font font = BirdFont.get_current_font ();		
		if (font.font_file == null) {
			MenuTab.save_callback = new SaveCallback ();
			MenuTab.save_callback.file_saved.connect (() => {
				MainWindow.native_window.export_font ();
			});
			MenuTab.save_callback.save ();
		} else {
			MainWindow.native_window.export_font ();
		}
	}
	
	/** Export TTF, EOT and SVG fonts. */
	public static void export_fonts () {
		ExportTool.export_ttf_font ();
		ExportTool.export_svg_font ();
		TooltipArea.show_text (t_("Three font files have been created."));	
	}
}

}
