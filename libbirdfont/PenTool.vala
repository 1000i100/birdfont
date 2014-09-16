/*
    Copyright (C) 2012, 2013, 2014 Johan Mattsson

    This library is free software; you can redistribute it and/or modify 
    it under the terms of the GNU Lesser General Public License as 
    published by the Free Software Foundation; either version 3 of the 
    License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful, but 
    WITHOUT ANY WARRANTY; without even the implied warranty of 
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
    Lesser General Public License for more details.
*/

using Math;
using Cairo;

namespace BirdFont {

/** Create new points. */
public class PenTool : Tool {

	private static double contact_surface {
		get {
			return MainWindow.units * 20;
		}
	}

	public static bool move_selected = false;
	public static bool move_selected_handle = false;

	public static bool move_point_on_path = false;

	public static bool edit_active_corner = false;
	
	public static Gee.ArrayList<PointSelection> selected_points; 

	public static EditPointHandle active_handle;
	public static EditPointHandle selected_handle;
	public static PointSelection handle_selection;
	
	public static EditPoint? active_edit_point;
	public static Path active_path;
	
	public static EditPoint selected_point;

	private static double last_point_x = 0;
	private static double last_point_y = 0;

	private static bool show_selection_box = false;
	private static double selection_box_x = 0;
	private static double selection_box_y = 0;
	private static double selection_box_last_x = 0;
	private static double selection_box_last_y = 0;

	private static bool point_selection_image = false;

	public static double precision = 1;
	
	// The pixel where the user pressed the mouse button
	public static int begin_action_x = 0; 
	public static int begin_action_y = 0;
	
	private static ImageSurface? tie_icon = null;
	
	/** First move action must move the current point in to the grid. */
	bool first_move_action = false;
	
	/** Move curve handle instead of control point. */
	private bool last_selected_is_handle = false;

	static Gee.ArrayList<Path> clockwise;
	static Gee.ArrayList<Path> counter_clockwise;
	
	public static double path_stroke_width = 0;
	public static double simplification_threshold = 0.5;
			
	public PenTool (string name) {	
		base (name, t_("Add new points"));
		
		selected_points = new Gee.ArrayList<PointSelection> (); 

		active_handle = new EditPointHandle.empty ();
		selected_handle = new EditPointHandle.empty ();
		handle_selection = new PointSelection.empty ();
		
		active_edit_point = new EditPoint ();
		active_path = new Path ();
		
		selected_point = new EditPoint ();
		clockwise = new Gee.ArrayList<Path> ();
		counter_clockwise = new Gee.ArrayList<Path> ();
		
		tie_icon = Icons.get_icon ("tie_is_active.png");
		
		select_action.connect ((self) => {
		});

		deselect_action.connect ((self) => {
			force_direction ();		
			move_point_on_path = false;
		});
		
		press_action.connect ((self, b, x, y) => {			
			// retain path direction
			Glyph glyph = MainWindow.get_current_glyph ();
			clockwise = new Gee.ArrayList<Path> ();
			counter_clockwise = new Gee.ArrayList<Path> ();

			begin_action_x = x;
			begin_action_y = y;

			foreach (Path p in glyph.path_list) {
				if (p.is_clockwise ()) {
					clockwise.add (p);
				} else {
					counter_clockwise.add (p);
				}
			}
			
			first_move_action = true;
			
			last_point_x = Glyph.path_coordinate_x (x);
			last_point_y = Glyph.path_coordinate_y (y);

			move_action (this, x, y);

			press (b, x, y, false);

			if (BirdFont.android) {
				point_selection_image = true;
			}
			
			selection_box_x = x;
			selection_box_y = y;
			
			last_point_x = Glyph.path_coordinate_x (x);
			last_point_y = Glyph.path_coordinate_y (y);
		});
		
		double_click_action.connect ((self, b, x, y) => {
			last_point_x = Glyph.path_coordinate_x (x);
			last_point_y = Glyph.path_coordinate_y (y);

			press (b, x, y, true);
		});

		release_action.connect ((self, b, ix, iy) => {
			double x, y;
			
			x = Glyph.path_coordinate_x (ix);
			y = Glyph.path_coordinate_y (iy);
						
			if (has_join_icon ()) {
				join_paths (x, y);
			}

			active_handle = new EditPointHandle.empty ();
			
			if (show_selection_box) {
				select_points_in_box ();
			}

			move_selected = false;
			move_selected_handle = false;
			edit_active_corner = false;
			show_selection_box = false;
			
			// update path direction if it has changed
			foreach (Path p in clockwise) {
				if (!p.is_open () && !p.is_clockwise ()) {
					p.reverse ();
					update_selection ();
				}
			}

			foreach (Path p in counter_clockwise) {
				if (!p.is_open () &&  p.is_clockwise ()) {
					p.reverse ();
					update_selection ();
				}
			}
			
			point_selection_image = false;
		});

		move_action.connect ((self, x, y) => {
			selection_box_last_x = x;
			selection_box_last_y = y;
			
			if (Path.distance (begin_action_x, x, begin_action_y, y) > 10 * MainWindow.units) {
				point_selection_image = false;
			}
			
			move (x, y);
		});
		
		key_press_action.connect ((self, keyval) => {
			if (keyval == Key.DEL || keyval == Key.BACK_SPACE) {
				if (KeyBindings.has_shift ()) {
					delete_selected_points ();
				} else {
					delete_simplify ();
				}
			}
			
			if (is_arrow_key (keyval)) {
				if (KeyBindings.modifier != CTRL) {
					move_selected_points (keyval);
					active_edit_point = selected_point;
				} else {
					move_select_next_point (keyval);
				}
			}	
		});
		
		key_release_action.connect ((self, keyval) => {
			double x, y;
			if (is_arrow_key (keyval)) {
				if (KeyBindings.modifier != CTRL) {
					x = Glyph.reverse_path_coordinate_x (selected_point.x);
					y = Glyph.reverse_path_coordinate_y (selected_point.y);
					join_paths (x, y);
				}
			}	
		});
		
		draw_action.connect ((tool, cairo_context, glyph) => {
			draw_on_canvas (cairo_context, glyph);
		});
	}

	public void set_stroke_width (double width) {
		string w = SpinButton.convert_to_string (width);
		Preferences.set ("pen_tool_stroke_width", w);
		path_stroke_width = width;
	}
	
	private bool has_join_icon () {
		double mx, my;
		get_tie_position (out mx, out my);
		return (mx > -10 * MainWindow.units && my > -10 * MainWindow.units);
	}

	public static void select_points_in_box () {
		double x1, y1, x2, y2;
		Glyph g;
		
		g = MainWindow.get_current_glyph ();
		
		x1 = Glyph.path_coordinate_x (fmin (selection_box_x, selection_box_last_x));
		y1 = Glyph.path_coordinate_y (fmin (selection_box_y, selection_box_last_y));
		x2 = Glyph.path_coordinate_x (fmax (selection_box_x, selection_box_last_x));
		y2 = Glyph.path_coordinate_y (fmax (selection_box_y, selection_box_last_y));
		
		remove_all_selected_points ();
		
		foreach (Path p in g.path_list) {
			// TODO: Select path only of bounding box is in selection box
			foreach (EditPoint ep in p.points) {
				if (x1 <= ep.x <= x2 && y2 <= ep.y <= y1) {
					add_selected_point (ep, p);
					ep.set_selected (true);
				}
			}
		}
	}

	public static void delete_selected_points () {
		Glyph g = MainWindow.get_current_glyph ();

		foreach (PointSelection p in selected_points) {
			p.point.deleted = true;
		}
		
		process_deleted ();

		foreach (Path p in g.path_list) {
			if (p.has_deleted_point ()) {
				process_deleted ();
			}
		}
								
		g.update_view ();

		selected_points.clear ();
		selected_handle.selected = false;
		
		active_handle = new EditPointHandle.empty ();
		selected_handle = new EditPointHandle.empty ();
		
		active_edit_point = null;
		selected_point = new EditPoint ();
	}

	static void get_closes_point_in_segment (EditPoint ep0, EditPoint ep1, EditPoint ep2,
			double px, double py,
			out double nx, out double ny) {
		double npx0, npy0;
		double npx1, npy1;
		
		Path.find_closes_point_in_segment (ep0, ep1, px, py, out npx0, out npy0, 50);
		Path.find_closes_point_in_segment (ep1, ep2, px, py, out npx1, out npy1, 50);

		if (Path.distance (px, npx0, py, npy0) < Path.distance (px, npx1, py, npy1)) {
			nx = npx0;
			ny = npy0;
		} else {
			nx = npx1;
			ny = npy1;
		}
	}

	public static void get_path_distortion (EditPoint oe0, EditPoint oe1, EditPoint oe2,
			EditPoint ep1, EditPoint ep2,
			out double distortion_first, out double distortion_next) {
		double nx, ny;
		double df, dn;
		int step;
		
		df = 0;
		dn = 0;
		nx = 0;
		ny = 0;

		step = 4;
		
		Path.all_of (ep1, ep2, (xa, ya, ta) => {
			double f, n;
	
			get_closes_point_in_segment (oe0, oe1, oe2, xa, ya, out nx, out ny);
			
			if (ta < 0.5) {
				f = Path.distance (nx, xa, ny, ya);
				if (f > df) {
					df += f;
				}
			} else {
				n = Path.distance (nx, xa, ny, ya);
				if (n > dn) {
					dn += n;
				}
			}
			
			return true;
		}, step);	

		distortion_first = df;
		distortion_next = dn;
	}

	public static void delete_simplify () {
		Glyph g = MainWindow.get_current_glyph ();
				
		foreach (PointSelection p in selected_points) {
			remove_point_simplify (p);
		}
		
		g.update_view ();

		selected_points.clear ();
		selected_handle.selected = false;
		
		active_handle = new EditPointHandle.empty ();
		selected_handle = new EditPointHandle.empty ();
		
		active_edit_point = null;
		selected_point = new EditPoint ();
	}
	
	/** @return path distortion. */
	public static double remove_point_simplify (PointSelection p, double tolerance = 0.6) {
		double start_length, stop_length;
		double start_distortion, start_min_distortion, start_previous_length;
		double stop_distortion, stop_min_distortion, stop_previous_length;
		double distortion, min_distortion; 
		double prev_length_adjustment, next_length_adjustment;
		double prev_length_adjustment_reverse, next_length_adjustment_reverse;
		EditPoint ep1, ep2;
		EditPoint next, prev;
		double step, distance;
				
		return_if_fail (p.path.points.size > 0);
		
		if (p.path.points.size <= 2) {
			p.point.deleted = true;
			p.path.remove_deleted_points ();
			return 0;
		}
		
		p.point.deleted = true;
		
		if (p.point.next != null) {
			next = p.point.get_next ();
		} else {
			next = p.path.points.get (0);
		}

		if (p.point.prev != null) {
			prev = p.point.get_prev ();
		} else {
			prev = p.path.points.get (p.path.points.size - 1);
		}
		
		prev.get_right_handle ().convert_to_curve ();
		next.get_left_handle ().convert_to_curve ();

		if (prev.get_right_handle ().type == PointType.QUADRATIC
				&& next.get_left_handle ().type != PointType.QUADRATIC) {
			convert_point_type (prev, next.get_left_handle ().type);
		}

		if (prev.get_right_handle ().type != PointType.QUADRATIC
				&& next.get_left_handle ().type == PointType.QUADRATIC) {
			convert_point_type (next, prev.get_right_handle ().type);
		}
				
		ep1 = prev.copy ();
		ep2 = next.copy ();

		start_length = ep1.get_right_handle ().length;
		stop_length = ep2.get_left_handle ().length;
		
		stop_previous_length = start_length;
		start_previous_length = stop_length;

		stop_min_distortion = double.MAX;
		ep1.get_right_handle ().length = start_length;
		
		start_min_distortion = double.MAX;
		ep2.get_left_handle ().length = stop_length;
				
		prev_length_adjustment = 0;
		next_length_adjustment = 0;
		prev_length_adjustment_reverse = 0;
		next_length_adjustment_reverse = 0;

		min_distortion = double.MAX;
		distance = Path.distance (ep1.x, ep2.x, ep1.y, ep2.y);

		for (double m = 50.0; m >= tolerance / 2.0; m /= 10.0) {
			step = m / 10.0;
			min_distortion = double.MAX;
			
			double first = (m == 50.0) ? 0 : -m;
			for (double a = first; a < m; a += step) {
				for (double b = first; b < m; b += step) {
					
					if (start_length + a + stop_length + b > distance) {
						break;
					}
							
					ep1.get_right_handle ().length = start_length + a;
					ep2.get_left_handle ().length = stop_length + b;
					
					get_path_distortion (prev, p.point, next, 
						ep1, ep2, 
						out start_distortion, out stop_distortion);
					
					distortion = Math.fmax (start_distortion, stop_distortion);
					
					if (distortion < min_distortion
							&& start_length + a > 0
							&& stop_length + b > 0) {
						min_distortion = distortion;
						
						prev_length_adjustment_reverse = a;
						next_length_adjustment = b;
					}
				}
			}
						
			start_length += prev_length_adjustment_reverse;
			stop_length += next_length_adjustment;
		}
		
		prev.get_right_handle ().length = start_length;
		
		if (prev.get_right_handle ().type != PointType.QUADRATIC) {
			next.get_left_handle ().length = stop_length;
		} else {
			next.get_left_handle ().move_to_coordinate (
				prev.get_right_handle ().x, prev.get_right_handle ().y);
		}
		
		p.point.deleted = true;
		p.path.remove_deleted_points ();
		p.path.update_region_boundaries ();
		
		return min_distortion;
	}
	
	/** Retain selected points even if path is copied after running reverse. */
	public static void update_selection () {
		Glyph g = MainWindow.get_current_glyph ();
		
		selected_points.clear ();

		foreach (Path p in g.path_list) {
			foreach (EditPoint e in p.points) {
				if (e.is_selected ()) {
					selected_points.add (new PointSelection (e, p));
				}
			}
		}
	}
	
	static void process_deleted () {
		Glyph g = MainWindow.get_current_glyph ();
		while (g.process_deleted ());
	}
	
	public static void close_all_paths () {
		Glyph g = MainWindow.get_current_glyph ();
		foreach (Path p in g.path_list) {
			p.close ();
		}
		g.close_path ();
		g.redraw_area (0, 0, g.allocation.width, g.allocation.height);
	}
	
	public void set_precision (double p) {
		precision = p;
		DrawingTools.precision.set_value_round (p, false, false);
	}
	
	public void move (int x, int y) {
		Glyph glyph = MainWindow.get_current_glyph ();
		double coordinate_x, coordinate_y;
		double delta_coordinate_x, delta_coordinate_y;
		int px = 0;
		int py = 0;
		EditPoint p;
		double angle = 0;
		
		control_point_event (x, y);
		curve_active_corner_event (x, y);
		set_default_handle_positions ();
		
		// move control point handles
		if (move_selected_handle) {
			set_type_for_moving_handle ();

			// don't update angle if the user is pressing shift
			if (KeyBindings.modifier == SHIFT) {
				angle = selected_handle.angle;
			}

			if (GridTool.is_visible ()) {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				GridTool.tie_coordinate (ref coordinate_x, ref coordinate_y);
				delta_coordinate_x = coordinate_x - selected_handle.x;
				delta_coordinate_y = coordinate_y - selected_handle.y;
				selected_handle.move_delta_coordinate (delta_coordinate_x, delta_coordinate_y);
			} else if (GridTool.has_ttf_grid ()) {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				GridTool.ttf_grid_coordinate (ref coordinate_x, ref coordinate_y);
				delta_coordinate_x = coordinate_x - selected_handle.x;
				delta_coordinate_y = coordinate_y - selected_handle.y;				
				selected_handle.move_delta_coordinate (delta_coordinate_x, delta_coordinate_y);
			} else {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				delta_coordinate_x = coordinate_x - selected_handle.x;
				delta_coordinate_y = coordinate_y - selected_handle.y;				
				selected_handle.move_delta_coordinate (delta_coordinate_x, delta_coordinate_y);
			}

			if (KeyBindings.modifier == SHIFT) {
				selected_handle.angle = angle;
				selected_handle.process_connected_handle ();
				
				if (selected_handle.parent.tie_handles) {
					if (selected_handle.is_left_handle ()) {
						selected_handle.parent.get_right_handle ().angle = angle - PI;
					} else {
						selected_handle.parent.get_left_handle ().angle = angle + PI;
					}
				}
			}
			
			handle_selection.path.update_region_boundaries ();
			
			// FIXME: redraw line only
			glyph.redraw_area (0, 0, glyph.allocation.width, glyph.allocation.height);
			
			if (GridTool.is_visible ()) {
				last_point_x = selected_handle.x;
				last_point_y = selected_handle.y;
			} else if (GridTool.has_ttf_grid ()) {
				last_point_x = selected_handle.x;
				last_point_y = selected_handle.y;
			} else {
				last_point_x = Glyph.path_coordinate_x (x);
				last_point_y = Glyph.path_coordinate_y (y);
			}
			
			return;
		}

		// move edit point
		if (move_selected) {
			if (GridTool.is_visible ()) {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				GridTool.tie_coordinate (ref coordinate_x, ref coordinate_y);
				delta_coordinate_x = coordinate_x - last_point_x;
				delta_coordinate_y = coordinate_y - last_point_y;
				
				foreach (PointSelection selected in selected_points) {
					selected.point.set_position (selected.point.x + delta_coordinate_x,
						selected.point.y + delta_coordinate_y);
					selected.point.recalculate_linear_handles ();
					selected.path.update_region_boundaries ();
				}
			} else if (GridTool.has_ttf_grid ()) {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				GridTool.ttf_grid_coordinate (ref coordinate_x, ref coordinate_y);
				delta_coordinate_x = coordinate_x - last_point_x;
				delta_coordinate_y = coordinate_y - last_point_y;
				
				foreach (PointSelection selected in selected_points) {
					selected.point.set_position (selected.point.x + delta_coordinate_x,
						selected.point.y + delta_coordinate_y);
					selected.point.recalculate_linear_handles ();
					selected.path.update_region_boundaries ();
				}
			} else {
				coordinate_x = Glyph.path_coordinate_x (x);
				coordinate_y = Glyph.path_coordinate_y (y);
				delta_coordinate_x = coordinate_x - last_point_x;
				delta_coordinate_y = coordinate_y - last_point_y;

				foreach (PointSelection selected in selected_points) {
					selected.point.set_position (selected.point.x + delta_coordinate_x,
						selected.point.y + delta_coordinate_y);
					
					selected.point.recalculate_linear_handles ();
					selected.path.update_region_boundaries ();
				}
			}
			if (GridTool.is_visible ()) {
				last_point_x = selected_point.x;
				last_point_y = selected_point.y;
			} else if (GridTool.has_ttf_grid ()) {
				last_point_x = selected_point.x;
				last_point_y = selected_point.y;
			} else {
				last_point_x = Glyph.path_coordinate_x (x);
				last_point_y = Glyph.path_coordinate_y (y);
			}
		}
	}
	
	private static void tie_pixels (ref int x, ref int y) {
		double coordinate_x, coordinate_y;
		coordinate_x = Glyph.path_coordinate_x (x);
		coordinate_y = Glyph.path_coordinate_y (y);
		GridTool.tie_coordinate (ref coordinate_x, ref coordinate_y);
		x = Glyph.reverse_path_coordinate_x (coordinate_x);
		y = Glyph.reverse_path_coordinate_y (coordinate_y);
	}
	
	public void press (int button, int x, int y, bool double_click) {
		Glyph? g = MainWindow.get_current_glyph ();
		Glyph glyph = (!) g;
		Toolbox tb = MainWindow.get_toolbox ();
		
		return_if_fail (g != null);

		if ((double_click && !BirdFont.android)
				|| tb.drawing_tools.inser_point_on_path_tool.is_selected ()) {
			glyph.insert_new_point_on_path (x, y);
			return;
		}
		
		if (button == 1) {
			add_point_event (x, y);
			return;
		}

		if (button == 2) {
			if (glyph.is_open ()) {
				force_direction ();
				glyph.close_path ();
			} else {
				glyph.open_path ();
			}
			return;
		}
		
		if (button == 3) {
			move_point_event (x, y);
			return;
		}
	}

	public void add_point_event (int x, int y) {
		Glyph? g = MainWindow.get_current_glyph ();
		Glyph glyph = (!) g;
		
		return_if_fail (g != null);
		
		remove_all_selected_points ();
		new_point_action (x, y);
		glyph.store_undo_state ();
	}
		
	public void move_point_event (int x, int y) {
		Glyph? g = MainWindow.get_current_glyph ();
		Glyph glyph = (!) g;
		
		return_if_fail (g != null);
		
		control_point_event (x, y);
		curve_corner_event (x, y);
		
		if (!move_selected_handle) {
			select_active_point (x, y);
			last_selected_is_handle = false;
		}

		if (selected_points.size == 0 && !active_handle.active) {
			show_selection_box = true;
		}

		glyph.store_undo_state ();
	}
	
	void set_type_for_moving_handle () {
		if (selected_handle.type == PointType.LINE_CUBIC) {
			selected_handle.set_point_type (PointType.CUBIC);
		}

		if (selected_handle.type == PointType.LINE_QUADRATIC) {
			selected_handle.set_point_type (PointType.QUADRATIC);
		}

		if (selected_handle.type == PointType.LINE_DOUBLE_CURVE) {
			selected_handle.set_point_type (PointType.DOUBLE_CURVE);
		}
	}
	
	/** Set fill property to transparend for counter paths. */ 
	public static void force_direction () {
		Glyph g = MainWindow.get_current_glyph ();
		
		// don't retain direction
		clockwise.clear ();
		counter_clockwise.clear ();

		foreach (Path p in g.path_list) {
			if (!p.has_direction ()) {
				if (is_counter_path (p)) {
					p.force_direction (Direction.COUNTER_CLOCKWISE);
				} else {
					p.force_direction (Direction.CLOCKWISE);
				}				
			}
		}
		
		update_selected_points ();
	}

	public static bool is_counter_path (Path path) {
		Glyph g = MainWindow.get_current_glyph ();
		PathList pl = new PathList ();
		
		foreach (Path p in g.path_list) {
			pl.add (p);
		}
		
		return Path.is_counter (pl, path);
	}

	public void remove_from_selected (EditPoint ep) 
		requires (selected_points.size > 0) {
		
		Gee.ArrayList<PointSelection> remove = new Gee.ArrayList<PointSelection>  ();
					
		foreach (PointSelection e in selected_points) {
			if (e.point.equals (e.point)) {
				remove.add (e);
			}
		}

		foreach (PointSelection e in remove) {
			selected_points.remove (e);
		}
	}
	
	public void select_active_point (double x, double y) {
		Glyph? g = MainWindow.get_current_glyph ();
		Glyph glyph = (!) g;
		bool reverse;
		
		control_point_event (x, y);

		// continue adding points from the other end of the selected path
		reverse = false;

		foreach (Path p in glyph.path_list) {
			
			if (p.is_open () && p.points.size >= 1 
				&& (active_edit_point == p.points.get (0) 
				|| active_edit_point == p.points.get (p.points.size - 1))) {
				active_path = p;
				glyph.set_active_path (p);
				
				update_selection ();
				reverse = true;
				control_point_event (x, y);
				break;
			}
		}
			
		foreach (Path p in glyph.path_list) {
			if (p.is_open () && p.points.size > 1 && active_edit_point == p.points.get (0)) {
				p.reverse ();
				update_selection ();
				reverse = true;
				control_point_event (x, y);
				break;
			}
		}
				
		if (active_edit_point == null) {
			if (KeyBindings.modifier != SHIFT) {
				remove_all_selected_points ();
				return;
			}
		}
		
		move_selected = true;
		move_point_on_path = true;
		
		if (active_edit_point != null) {
			if (KeyBindings.modifier == SHIFT) {
				if (((!)active_edit_point).is_selected ()) {
					((!)active_edit_point).set_selected (false);
					remove_from_selected ((!)active_edit_point);
					selected_point = new EditPoint ();
					last_selected_is_handle = false;
				} else {
					((!)active_edit_point).set_selected (true);
					selected_point = (!)active_edit_point;
					add_selected_point (selected_point, active_path);
					last_selected_is_handle = false;
				}
			} else {
				selected_point = (!)active_edit_point;
				
				if (!((!)active_edit_point).is_selected ()) {
					remove_all_selected_points ();
					((!)active_edit_point).set_selected (true);
					selected_point = (!)active_edit_point;
					add_selected_point (selected_point, active_path); // FIXME: double check active path
					last_selected_is_handle = false;
				}
			}
		}
		
		if (reverse) {
			clockwise.clear ();
			counter_clockwise.clear ();
		}
	}
	
	private static Path? find_path_to_join () {
		Path? m = null;
		Glyph glyph = MainWindow.get_current_glyph ();
		EditPoint ep_last, ep_first;

		foreach (Path path in glyph.path_list) {
			if (path.points.size == 0) {
				continue;
			}

			ep_last = path.points.get (path.points.size - 1);
			ep_first = path.points.get (0);	
			
			if (active_edit_point == ep_last) {
				m = path;
				break;
			}
			
			if (active_edit_point == ep_first) {
				m = path;
				break;				
			}
		}
		
		return m;	
	}
	
	private static void join_paths (double x, double y) {
		Glyph glyph = MainWindow.get_current_glyph ();
		Path? p;
		Path path;
		bool direction_changed = false;
		Path union, second_path;
		EditPoint last_point, first_point;
		EditPointHandle last_rh, fist_lh;
		int px, py;
		
		if (glyph.path_list.size == 0) {
			return;
		}

		p = find_path_to_join ();
		if (p == null) {
			warning ("No path to join.");
			return;
		}
		path = (!) p;
		
		if (!path.is_open ()) {
			warning ("Path is closed.");
			return;
		}
		
		if (active_edit_point == path.points.get (0)) {
			path.reverse ();
			update_selection ();
			path.recalculate_linear_handles ();
			direction_changed = true;
			active_edit_point = path.points.get (path.points.size - 1);
			active_path = path;
		}
		
		if (path.points.get (0) == active_edit_point) {
			warning ("Wrong direction.");
			return;
		}
		
		// join path with it self
		px = Glyph.reverse_path_coordinate_x (((!) active_edit_point).x);
		py = Glyph.reverse_path_coordinate_y (((!) active_edit_point).y);
		if (is_endpoint ((!) active_edit_point)
			&& is_close_to_point (path.points.get (0), px, py)) {
			// TODO: set point type
			path.points.get (0).left_handle.move_to_coordinate (
				path.points.get (path.points.size - 1).left_handle.x,
				path.points.get (path.points.size - 1).left_handle.y);
				
			path.points.get (0).left_handle.type = 
				path.points.get (path.points.size - 1).left_handle.type;

			path.points.get (0).recalculate_linear_handles ();
			path.points.get (path.points.size - 1).recalculate_linear_handles ();
			
			// force the connected handle to move
			path.points.get (0).set_position (
				path.points.get (0).x, path.points.get (0).y);
		
			path.points.remove_at (path.points.size - 1);
			
			path.close ();
			glyph.close_path ();
			
 			force_direction ();

			if (direction_changed) {
				path.reverse ();
				update_selection ();
			}
			
			remove_all_selected_points ();
			return;
		}
		
		union = new Path ();
		foreach (EditPoint ep in path.points) {
			union.add_point (ep.copy ());
		}
				
		foreach (Path merge in glyph.path_list) {
			// don't join path with itself here
			if (path == merge) {
				continue;
			}

			// we need both start and end points
			if (merge.points.size < 1 || path.points.size < 1) {
				continue;
			}
			
			if (is_close_to_point (merge.points.get (merge.points.size - 1), px, py)) {
				merge.reverse ();
				update_selection ();
				direction_changed = !direction_changed;
			}

			return_if_fail (merge.points.size > 0);

			if (is_close_to_point (merge.points.get (0), px, py)) {
				merge.points.get (0).set_tie_handle (false);
				merge.points.get (0).set_reflective_handles (false);
				
				merge.points.get (merge.points.size - 1).set_tie_handle (false);
				merge.points.get (merge.points.size - 1).set_reflective_handles (false);
								
				path.points.get (path.points.size - 1).set_tie_handle (false);
				path.points.get (path.points.size - 1).set_reflective_handles (false);

				path.points.get (0).set_tie_handle (false);
				path.points.get (0).set_reflective_handles (false);
				
				second_path = merge.copy ();
				
				first_point = second_path.get_first_point ();
				
				if (union.get_last_point ().get_left_handle ().is_curve ()) {
					first_point.get_left_handle ().convert_to_curve ();
				} else {
					first_point.get_left_handle ().convert_to_line ();
				}
				
				first_point.get_left_handle ().move_to_coordinate_internal (union.get_last_point ().get_left_handle ().x, union.get_last_point ().get_left_handle ().y);

				union.delete_last_point ();
				
				union.append_path (second_path);
				glyph.add_path (union);
				
				glyph.delete_path (path);
				glyph.delete_path (merge);
				glyph.clear_active_paths ();
				
				union.reopen ();
				union.create_list ();
				
 				force_direction ();
				
				if (direction_changed) {
					path.reverse ();
					update_selection ();
				}
				
				union.update_region_boundaries ();
				
				return;
			}
		}

		if (direction_changed) {
			path.reverse ();
			update_selection ();
		}
	}
	
	/** Merge paths if ends are close. */
	public static bool is_close_to_point (EditPoint ep, double x, double y) {
		double px, py, distance;
		
		px = Glyph.reverse_path_coordinate_x (ep.x);
		py = Glyph.reverse_path_coordinate_y (ep.y);		

		distance = sqrt (fabs (pow (px - x, 2)) + fabs (pow (py - y, 2)));
		
		return (distance < 8 * MainWindow.units);
	}

	/** Show the user that curves will be merged on release. */
	public void draw_on_canvas (Context cr, Glyph glyph) {
		if (show_selection_box) {
			draw_selection_box (cr);
		}
		
		if (point_selection_image) {
			draw_point_selection_circle (cr);
		}
		
		draw_merge_icon (cr);
	}
	
	/** Higlight the selected point on Android. */
	void draw_point_selection_circle (Context cr) {
		ImageSurface img;
		ImageSurface? i = null;
		double x, y;
		double ratio;
		PointSelection ps;
		
		if (active_handle.active) {
			i = Path.edit_point_handle_image;
		} else if (selected_points.size > 0) {
			ps = selected_points.get (selected_points.size - 1);
			
			i = (ps.point.type == PointType.CUBIC) 
				? Path.cubic_edit_point_image : Path.edit_point_image;
		}
		
		if (i != null) {
			img = (!) i;	
			
			cr.save ();
			ratio = 60 * MainWindow.units / img.get_width ();
			cr.scale (ratio, ratio);
			x = begin_action_x - ratio * img.get_width () / 2;
			x /= ratio;
			y = begin_action_y - ratio * img.get_height () / 2;
			y /= ratio;
			cr.set_source_surface (img, x, y);
			cr.paint ();
			cr.restore ();
		}
	}
	
	void draw_selection_box (Context cr) {
		double x, y, w, h;

		x = fmin (selection_box_x, selection_box_last_x);
		y = fmin (selection_box_y, selection_box_last_y);
		w = fmax (selection_box_x, selection_box_last_x) - x;
		h = fmax (selection_box_y, selection_box_last_y) - y;
		
		cr.save ();
		cr.set_source_rgba (0, 0, 0.3, 1);
		cr.set_line_width (2);
		cr.rectangle (x, y, w, h);
		cr.stroke ();
		cr.restore ();
	}
	
	public static void draw_join_icon (Context cr, double x, double y) {
		double scale = (BirdFont.android) ? 5 : 1;
		draw_icon (tie_icon, cr, x, y, scale);
	}

	public static void draw_icon (ImageSurface? i, Context cr, double x, double y, double scale = 1) {
		ImageSurface img;
		double px, py, ratio;
		
		if (i != null) {
			img = (!) tie_icon;	
					
			cr.save ();
			
			ratio = scale;
			ratio *= 0.23; // 72 to 320 dpi
			ratio *=  MainWindow.units;
			cr.scale (ratio, ratio);
			
			px = x - ratio * img.get_width () / 2;
			py = y - ratio * img.get_height () / 2;
			px /= ratio;
			py /= ratio;
			
			cr.set_source_surface (img, px, py);
			cr.paint ();
			cr.restore ();
		} else {
			warning ("No image.");
		}
	}
		

	void draw_merge_icon (Context cr) {
		double x, y;
		get_tie_position (out x, out y);
		draw_join_icon (cr, x, y);
	}
	
	/** Obtain the position where to ends meet. */
	void get_tie_position (out double x, out double y) {
		Glyph glyph;
		EditPoint active;
		double px, py;

		x = -100;
		y = -100;
				
		if (active_edit_point == null) {
			return;
		}
		
		if (!is_endpoint ((!) active_edit_point)) {
			return;
		}
		
		glyph = MainWindow.get_current_glyph ();
		active = (!) active_edit_point;
		
		return_if_fail (!is_null (glyph));
		
		px = Glyph.reverse_path_coordinate_x (active.x);
		py = Glyph.reverse_path_coordinate_y (active.y);

		foreach (Path path in glyph.path_list) {
			
			if (!path.is_open ()) {
				continue;
			}
			
			if (path.points.size == 0) {
				continue;
			}
			
			foreach (EditPoint ep in path.points) {
				if (ep == active || !is_endpoint (ep)) {
					continue;
				}
				
				if (is_close_to_point (ep, px, py)) {
					x = Glyph.reverse_path_coordinate_x (ep.x);
					y = Glyph.reverse_path_coordinate_y (ep.y);
					return;
				}
			}
		}
	}
	
	public static bool is_endpoint (EditPoint ep) {
		EditPoint start;
		EditPoint end;
		Glyph glyph = MainWindow.get_current_glyph ();
		
		foreach (Path path in glyph.path_list) {
			if (path.points.size < 1) {
				continue;
			}
			
			start = path.points.get (0);
			end = path.points.get (path.points.size - 1);
			
			if (ep == start || ep == end) {
				return true;
			}		
		}
		
		return false;
	}
		
	public static void set_active_edit_point (EditPoint? e, Path path) {
		Glyph g = MainWindow.get_current_glyph ();
		foreach (var p in g.path_list) {
			foreach (var ep in p.points) {
				ep.set_active (false);
			}
		}
		
		active_edit_point = e;
		active_path = path;
		
		if (e != null) {
			((!)e).set_active (true);
		}

		g.redraw_area (0, 0, g.allocation.width, g.allocation.height);
	}

	PointSelection? get_closest_point (double ex, double ey, out Path? path) {
		double x = Glyph.path_coordinate_x (ex);
		double y = Glyph.path_coordinate_y (ey);
		double d = double.MAX;
		double nd;
		PointSelection? ep = null;
		Glyph g = MainWindow.get_current_glyph ();
		
		path = null;
		
		foreach (Path current_path in g.path_list) {
			if (is_close_to_path (current_path, ex, ey)) {
				foreach (EditPoint e in current_path.points) {
					nd = e.get_distance (x, y);
					
					if (nd < d) {
						d = nd;
						ep = new PointSelection (e, current_path);
						path = current_path;
					}
				}
			}
		}
		
		return ep;
	}

	public double get_distance_to_closest_edit_point (double event_x, double event_y) {
		Path? p;
		PointSelection e;
		PointSelection? ep = get_closest_point (event_x, event_y, out p);

		double x = Glyph.path_coordinate_x (event_x);
		double y = Glyph.path_coordinate_y (event_y);
		
		if (ep == null) {
			return double.MAX;
		}
		
		e = (!) ep;
		
		return e.point.get_distance (x, y);
	}

	public void control_point_event (double event_x, double event_y) {
		Path? p;
		PointSelection? ep = get_closest_point (event_x, event_y, out p);
		Glyph g = MainWindow.get_current_glyph ();
		double x = Glyph.path_coordinate_x (event_x);
		double y = Glyph.path_coordinate_y (event_y);
		double distance;
		PointSelection e;
		int px, py;
		double coordinate_x, coordinate_y;
		set_active_edit_point (null, new Path ());
		
		if (ep == null) {
			return;	
		}
		
		e = (!) ep;
		distance = e.point.get_distance (x, y) * g.view_zoom;

		if (distance < contact_surface) {
			set_active_edit_point (e.point, e.path);
		
			if (first_move_action && GridTool.is_visible () && move_selected) {
				coordinate_x = e.point.x;
				coordinate_y = e.point.y;
				GridTool.tie_coordinate (ref coordinate_x, ref coordinate_y);
				px = Glyph.reverse_path_coordinate_x (coordinate_x);
				py = Glyph.reverse_path_coordinate_y (coordinate_y);

				first_move_action = false;
			} else if (first_move_action && GridTool.has_ttf_grid () && move_selected) {
				coordinate_x = e.point.x;
				coordinate_y = e.point.y;
				
				GridTool.ttf_grid_coordinate (ref coordinate_x, ref coordinate_y);

				px = Glyph.reverse_path_coordinate_x (coordinate_x);
				py = Glyph.reverse_path_coordinate_y (coordinate_y);
				
				first_move_action = false;
			} 
		}
	}
	
	public void new_point_action (int x, int y) {
		Glyph glyph;
		PointSelection new_point;
		glyph = MainWindow.get_current_glyph ();
		glyph.open_path ();
		
		remove_all_selected_points ();
		
		new_point = add_new_edit_point (x, y);
		new_point.point.set_selected (true);

		selected_point = new_point.point;
		active_edit_point = new_point.point;
		
		return_if_fail (glyph.active_paths.size > 0);		
		add_selected_point (selected_point, glyph.active_paths.get (glyph.active_paths.size - 1));

		move_selected = true;
	}
	
	public static PointSelection add_new_edit_point (int x, int y) {
		Glyph glyph;
		PointSelection new_point;
		
		glyph = MainWindow.get_current_glyph ();
		
		new_point = glyph.add_new_edit_point (x, y);
		new_point.path.update_region_boundaries ();

		selected_point = new_point.point;
		active_edit_point = new_point.point;	

		set_point_type (selected_point);
		set_default_handle_positions ();
		
		selected_points.clear ();
		add_selected_point (new_point.point, new_point.path);
		
		return new_point;
	}

	static void set_point_type (EditPoint p) {
		if (p.prev != null && p.get_prev ().right_handle.type == PointType.QUADRATIC) {
			p.left_handle.type = PointType.QUADRATIC;
			p.right_handle.type = PointType.LINE_QUADRATIC;
			p.type = PointType.QUADRATIC;
		} else if (DrawingTools.get_selected_point_type () == PointType.QUADRATIC) {
			p.left_handle.type = PointType.LINE_QUADRATIC;
			p.right_handle.type = PointType.LINE_QUADRATIC;
			p.type = PointType.LINE_QUADRATIC;
		} else if (DrawingTools.get_selected_point_type () == PointType.DOUBLE_CURVE) {
			p.left_handle.type = PointType.LINE_DOUBLE_CURVE;
			p.right_handle.type = PointType.LINE_DOUBLE_CURVE;
			p.type = PointType.DOUBLE_CURVE;
		} else {
			p.left_handle.type = PointType.LINE_CUBIC;
			p.right_handle.type = PointType.LINE_CUBIC;
			p.type = PointType.CUBIC;		
		}
	}

	public static void set_default_handle_positions () {
		Glyph g = MainWindow.get_current_glyph ();
		foreach (var p in g.path_list) {
			if (p.is_editable ()) {
				p.create_list ();
				set_default_handle_positions_on_path (p);
			}
		}
	}

	static void set_default_handle_positions_on_path (Path path) {
		foreach (EditPoint e in path.points) {
			e.recalculate_linear_handles ();
		}
	}
	
	private bool is_over_handle (double event_x, double event_y) {		
		Glyph g = MainWindow.get_current_glyph (); 
		double distance_to_edit_point = g.view_zoom * get_distance_to_closest_edit_point (event_x, event_y);
		
		if (!Path.show_all_line_handles) {
			foreach (PointSelection selected_corner in selected_points) {
				if (is_close_to_handle (selected_corner.point, event_x, event_y, distance_to_edit_point)) {
					return true;
				}
			}
		} else {
			foreach (Path p in g.path_list) {
				if (is_close_to_path (p, event_x, event_y)) {
					foreach (EditPoint ep in p.points) {
						if (is_close_to_handle (ep, event_x, event_y, distance_to_edit_point)) {
							return true;
						}
					}
				}
			}
		}
	
		return false;
	}

	bool is_close_to_path (Path p, double event_x, double event_y) {
		double c = contact_surface * Glyph.ivz ();
		double x = Glyph.path_coordinate_x (event_x);
		double y = Glyph.path_coordinate_y (event_y);
		
		if (unlikely (!p.has_region_boundaries ())) {
			if (p.points.size > 0) {
				warning (@"No bounding box. $(p.points.size)");
				p.update_region_boundaries ();
			}
		}
		
		return p.xmin - c <= x <= p.xmax + c && p.ymin - c <= y <= p.ymax + c;
	}

	private bool is_close_to_handle (EditPoint selected_corner, double event_x, double event_y, double distance_to_edit_point) {
		double x = Glyph.path_coordinate_x (event_x);
		double y = Glyph.path_coordinate_y (event_y);
		Glyph g = MainWindow.get_current_glyph (); 
		double d_point = distance_to_edit_point;
		double dl, dr;
			
		dl = g.view_zoom * selected_corner.get_left_handle ().get_point ().get_distance (x, y);
		dr = g.view_zoom * selected_corner.get_right_handle ().get_point ().get_distance (x, y);
		
		if (dl < contact_surface && dl < d_point) {
			return true;
		}

		if (dr < contact_surface && dr < d_point) {
			return true;
		}
		
		return false;
	} 

	PointSelection get_closest_handle (double event_x, double event_y) {
		EditPointHandle left, right;
		double x = Glyph.path_coordinate_x (event_x);
		double y = Glyph.path_coordinate_y (event_y);		
		EditPointHandle eh = new EditPointHandle.empty();
		Glyph g = MainWindow.get_current_glyph ();
		double d = double.MAX;
		double dn;
		Path path = new Path ();
		bool left_handle = false;
		EditPoint parent_point;
		EditPoint tied_point;
		
		foreach (Path p in g.path_list) {
			if (is_close_to_path (p, event_x, event_y) || p == active_path) {
				foreach (EditPoint ep in p.points) {
					if (ep.is_selected () || Path.show_all_line_handles) {
						left = ep.get_left_handle ();
						right = ep.get_right_handle ();

						dn = left.get_point ().get_distance (x, y);
						
						if (dn < d) {
							eh = left;
							d = dn;
							path = p;
							left_handle = true;
						}

						dn = right.get_point ().get_distance (x, y);
						
						if (dn < d) {
							eh = right;
							d = dn;
							path = p;
							left_handle = false;
						}
					}
				}
			}
		}
		
		// Make sure the selected handle belongs to the selected point if
		// the current segment is quadratic.
		if (eh.type == PointType.QUADRATIC) {
			parent_point = eh.get_parent ();
			
			if (left_handle) {
				if (parent_point.prev !=  null) {
					tied_point = parent_point.get_prev ();
					if (tied_point.selected_point) {
						eh = tied_point.get_right_handle ();
					}
				}
			} else {
				if (parent_point.next !=  null) {
					tied_point = parent_point.get_next ();
					if (tied_point.selected_point) {
						eh = tied_point.get_left_handle ();
					}
				}
			}
		}
		
		return new PointSelection.handle_selection (eh, path);
	}

	private void curve_active_corner_event (double event_x, double event_y) {
		PointSelection eh;
		
		active_handle.active = false;
		
		if (!is_over_handle (event_x, event_y)) {
			return;
		}		
		
		eh = get_closest_handle (event_x, event_y);
		eh.handle.active = true;
		active_handle = eh.handle;
		active_path = eh.path;
	}

	private void curve_corner_event (double event_x, double event_y) {
		MainWindow.get_current_glyph ().open_path ();
		PointSelection p;
		
		if (!is_over_handle (event_x, event_y)) {
			return;
		}

		move_selected_handle = true;
		last_selected_is_handle = true;
		selected_handle.selected = false;
		p = get_closest_handle (event_x, event_y);
		selected_handle = p.handle;
		handle_selection = p;
		active_path = p.path;
		selected_handle.selected = true;
	}

	public static void add_selected_point (EditPoint p, Path path) {
		foreach (PointSelection ep in selected_points) {
			if (p == ep.point) {
				return;
			}
		}
		
		selected_points.add (new PointSelection (p, path));
	}
	
	public static void remove_all_selected_points () {
		Glyph g = MainWindow.get_current_glyph ();
		
		foreach (PointSelection ep in selected_points) {
			ep.point.set_active (false);
			ep.point.set_selected (false);
		}
		
		selected_points.clear ();
		
		foreach (Path p in g.path_list) {
			foreach (EditPoint e in p.points) {
				e.set_active (false);
				e.set_selected (false);
			}
		}
	}

	static void move_select_next_point (uint keyval) {
		PointSelection next = new PointSelection.empty ();
		Glyph g = MainWindow.get_current_glyph();
		
		if (selected_points.size == 0) {
			return;
		}

		switch (keyval) {
			case Key.UP:
				next = get_next_point_up ();
				break;
			case Key.DOWN:
				next = get_next_point_down ();
				break;
			case Key.LEFT:
				next = get_next_point_left ();
				break;
			case Key.RIGHT:
				next = get_next_point_right ();
				break;
			default:
				break;
		}

		set_selected_point (next.point, next.path);		
		g.redraw_area (0, 0, g.allocation.width, g.allocation.height);	
	}

	private static PointSelection get_next_point (double angle) 
		requires (selected_points.size != 0) {
		PointSelection e = selected_points.get (selected_points.size - 1);	
		double right_angle = e.point.right_handle.angle;
		double left_angle = e.point.left_handle.angle;
		double min_right, min_left;
		double min;
		
		return_val_if_fail (e.point.next != null, new EditPoint ());
		return_val_if_fail (e.point.prev != null, new EditPoint ());
			
		// angle might be greater than 2 PI or less than 0
		min_right = double.MAX;
		min_left = double.MAX;
		for (double i = -2 * PI; i <= 2 * PI; i += 2 * PI) {
			min = fabs (right_angle - (angle + i));
			if (min < min_right) {
				min_right = min;
			}
			
			min = fabs (left_angle - (angle + i));
			if (min < min_left) {
				min_left = min;
			}
		}
		
		if (min_right < min_left) {
			return new PointSelection (e.point.get_next (), e.path);
		}
		
		return new PointSelection (e.point.get_prev (), e.path);
	}
	
	private static PointSelection get_next_point_up () {
		return get_next_point (PI / 2);
	}

	private static PointSelection get_next_point_down () {
		return get_next_point (PI + PI / 2);
	}

	private static PointSelection get_next_point_left () {
		return get_next_point (PI);
	}

	private static PointSelection get_next_point_right () {
		return get_next_point (0);
	}

	private static void set_selected_point (EditPoint ep, Path p) {
		remove_all_selected_points ();
		add_selected_point (ep, p);
		set_active_edit_point (ep, p);
		edit_active_corner = true;
		ep.set_selected (true);
		set_default_handle_positions ();		
	}

	public static void select_point_up () {	
		move_select_next_point (Key.UP);
	}

	public static void select_point_down () {
		move_select_next_point (Key.DOWN);
	}

	public static void select_point_right () {
		move_select_next_point (Key.RIGHT);
	}

	public static void select_point_left () {
		move_select_next_point (Key.LEFT);
	}

	/**
	 * Move the selected editpoint one pixel with keyboard irrespectivly of 
	 * current zoom.
	 */
	void move_selected_points (uint keyval) {
		Glyph g = MainWindow.get_current_glyph();
		Path? last_path = null;
		
		if (!last_selected_is_handle) {
			if (keyval == Key.UP) {
				foreach (PointSelection e in selected_points) {
					e.point.set_position (e.point.x, e.point.y + Glyph.ivz ());
					e.point.recalculate_linear_handles ();
				}
			}
			
			if (keyval == Key.DOWN) {
				foreach (PointSelection e in selected_points) {
					e.point.set_position (e.point.x, e.point.y - Glyph.ivz ());
					e.point.recalculate_linear_handles ();
				}
			}

			if (keyval == Key.LEFT) {
				foreach (PointSelection e in selected_points) {
					e.point.set_position (e.point.x - Glyph.ivz (), e.point.y);
					e.point.recalculate_linear_handles ();
				}
			}

			if (keyval == Key.RIGHT) {
				foreach (PointSelection e in selected_points) {
					e.point.set_position (e.point.x + Glyph.ivz (), e.point.y);
					e.point.recalculate_linear_handles ();
				}
			}
			
			last_path = null;
			foreach (PointSelection e in selected_points) {
				if (e.path != last_path) {
					e.path.update_region_boundaries ();
					last_path = e.path;
				}
			}
			
		} else {
			set_type_for_moving_handle ();
			active_handle.active = false;
			active_handle = new EditPointHandle.empty ();
			
			if (keyval == Key.UP) {
				selected_handle.move_delta_coordinate (0, 1 * Glyph.ivz ());
			}
			
			if (keyval == Key.DOWN) {
				selected_handle.move_delta_coordinate (0, -1 * Glyph.ivz ());
			}

			if (keyval == Key.LEFT) {
				selected_handle.move_delta_coordinate (-1 * Glyph.ivz (), 0);
			}

			if (keyval == Key.RIGHT) {
				selected_handle.move_delta_coordinate (1 * Glyph.ivz (), 0);
			}				
		}
		
		// TODO: redraw only the relevant parts
		g.redraw_area (0, 0, g.allocation.width, g.allocation.height);
	}
	
	public static void convert_point_to_line (EditPoint ep, bool both) {
		ep.set_tie_handle (false);
		ep.set_reflective_handles (false);
		
		if (ep.next == null) {
			// FIXME: write a new function for this case
			// warning ("Next is null.");
		}

		if (ep.prev == null) {
			warning ("Prev is null.");
		}
		
		if (ep.type == PointType.CUBIC || ep.type == PointType.LINE_CUBIC) {
			ep.type = PointType.LINE_CUBIC;
			
			if (both) {
				ep.get_left_handle ().type = PointType.LINE_CUBIC;
				ep.get_right_handle ().type = PointType.LINE_CUBIC;
			}
			
			if (ep.next != null && ep.get_next ().is_selected ()) {
				ep.get_right_handle ().type = PointType.LINE_CUBIC;
			}

			if (ep.prev != null && ep.get_prev ().is_selected ()) {
				ep.get_left_handle ().type = PointType.LINE_CUBIC;
			}
						
		}

		if (ep.type == PointType.DOUBLE_CURVE| ep.type == PointType.LINE_DOUBLE_CURVE) {
			ep.type = PointType.LINE_DOUBLE_CURVE;
			if (both) {
				ep.get_left_handle ().type = PointType.LINE_DOUBLE_CURVE;
				ep.get_right_handle ().type = PointType.LINE_DOUBLE_CURVE;
			}

			if (ep.next != null && ep.get_next ().is_selected ()) {
				ep.get_right_handle ().type = PointType.LINE_DOUBLE_CURVE;
			}

			if (ep.prev != null && ep.get_prev ().is_selected ()) {
				ep.get_left_handle ().type = PointType.LINE_DOUBLE_CURVE;
			}
		}

		if (ep.type == PointType.QUADRATIC || ep.type == PointType.LINE_QUADRATIC) {
			ep.type = PointType.LINE_QUADRATIC;
			
			if (both) {
				ep.get_left_handle ().type = PointType.LINE_QUADRATIC;
				ep.get_right_handle ().type = PointType.LINE_QUADRATIC;
				
				if (ep.next != null) {
					ep.get_next ().get_left_handle ().type = PointType.LINE_QUADRATIC;		
				}
				
				if (ep.prev != null) {
					ep.get_prev ().get_right_handle ().type = PointType.LINE_QUADRATIC;		
				}
			}
			
			if (ep.next != null && ep.get_next ().is_selected ()) {
				ep.get_right_handle ().type = PointType.LINE_QUADRATIC;
				ep.get_next ().get_left_handle ().type = PointType.LINE_QUADRATIC;
			}

			if (ep.prev != null && ep.get_prev ().is_selected ()) {
				ep.get_left_handle ().type = PointType.LINE_QUADRATIC;
				ep.get_prev ().get_right_handle ().type = PointType.LINE_QUADRATIC;
			}		
			
		}
						
		ep.recalculate_linear_handles ();
	}
	
	public static void convert_segment_to_line () {
		if (selected_points.size == 0) {
			return;
		}
		
		if (selected_points.size == 1) {
			convert_point_to_line (selected_points.get (0).point, true);
		} else {
			foreach (PointSelection p in selected_points) {
				convert_point_to_line (p.point, false);
			}
		}
	}
	
	public static bool is_line (PointType t) {
		return t == PointType.LINE_QUADRATIC 
			|| t == PointType.LINE_DOUBLE_CURVE
			|| t == PointType.LINE_CUBIC;
	}

	public static PointType to_line (PointType t) {
		switch (t) {
			case PointType.QUADRATIC:
				return PointType.LINE_QUADRATIC;
			case PointType.DOUBLE_CURVE:
				return PointType.LINE_DOUBLE_CURVE;
			case PointType.CUBIC:
				return PointType.LINE_CUBIC;
			default:
				break;
		}
		return t;
	}

	public static PointType to_curve (PointType t) {
		switch (t) {
			case PointType.LINE_QUADRATIC:
				return PointType.QUADRATIC;
			case PointType.LINE_DOUBLE_CURVE:
				return PointType.DOUBLE_CURVE;
			case PointType.LINE_CUBIC:
				return PointType.CUBIC;
			default:
				break;
		}
		
		if (unlikely (t == PointType.NONE)) {
			warning ("Type is not set.");
		}
		
		return t;
	}
	
	public static void set_converted_handle_length (EditPointHandle e, PointType pt) {
		
		if (e.type == PointType.QUADRATIC  && pt == PointType.DOUBLE_CURVE) {
			e.length *= 2;
			e.length /= 4;
		}

		if (e.type == PointType.QUADRATIC  && pt  == PointType.CUBIC) {
			e.length *= 2;
			e.length /= 3;
		}

		if (e.type == PointType.DOUBLE_CURVE  && pt  == PointType.QUADRATIC) {
			e.length *= 4;
			e.length /= 2;			
		}

		if (e.type == PointType.DOUBLE_CURVE  && pt == PointType.CUBIC) {
			e.length *= 4;
			e.length /= 3;		
		}

		if (e.type == PointType.CUBIC  && pt == PointType.QUADRATIC) {
			e.length *= 3;
			e.length /= 2;		
		}

		if (e.type == PointType.CUBIC  && pt == PointType.DOUBLE_CURVE) {
			e.length *= 3;
			e.length /= 4;			
		}		
	}
	
	public static void convert_point_segment_type (EditPoint first, EditPoint next, PointType point_type) {
		bool line;
		
		set_converted_handle_length (first.get_right_handle (), point_type);
		set_converted_handle_length (next.get_left_handle (), point_type);
		
		line = is_line (first.type) 
			&& is_line (first.get_right_handle ().type) 
			&& is_line (next.get_left_handle ().type);
									
		if (!line) {
			first.type = point_type;
		} else {
			first.type = to_line (point_type);
		}
		
		if (!line) {
			first.get_right_handle ().type = point_type;
		} else {
			first.get_right_handle ().type = to_line (point_type);
		}

		if (!line) {
			next.get_left_handle ().type = point_type;
		} else {
			next.get_left_handle ().type = to_line (point_type);
		}
			
		// process connected handle
		if (point_type == PointType.QUADRATIC) {
			first.set_position (first.x, first.y);
			first.recalculate_linear_handles ();
		}
	}
	
	public static void convert_point_type (EditPoint first, PointType point_type) {
		convert_point_segment_type (first, first.get_next (), point_type);
	}
	
	public static void convert_point_types () {
		Glyph glyph = MainWindow.get_current_glyph ();
		glyph.store_undo_state ();
		PointSelection selected = new PointSelection.empty ();
		bool reset_selected = false;
		EditPoint e;
		
		if (selected_points.size == 1) {
			selected = selected_points.get (0);
			if (selected.point.next != null) {
				selected_points.add (new PointSelection (selected.point.get_next (), selected.path));
				selected.point.get_next ().set_selected (true);
			}
			
			if (selected.point.prev != null) {
				selected_points.add (new PointSelection (selected.point.get_prev (), selected.path));
				selected.point.get_next ().set_selected (true);
			}
			
			reset_selected = true;
		}
		
		foreach (PointSelection ps in selected_points) {
			e = ps.point;
			// convert segments not control points
			if (e.next == null || !e.get_next ().is_selected ()) {
				continue;
			}

			convert_point_type (e, DrawingTools.point_type);
		}
		
		if (reset_selected) {
			remove_all_selected_points ();
			selected_points.add (selected);
			selected.point.set_selected (true);
		}
	}
	
	public static void update_selected_points () {
		Glyph g = MainWindow.get_current_glyph ();
		selected_points.clear ();
		
		foreach (Path p in g.path_list) {
			foreach (EditPoint ep in p.points) {
				if (ep.is_selected ()) {
					selected_points.add (new PointSelection (ep, p));
				}
			}
		}
	}
	
	public void select_all_points () {
		Glyph g = MainWindow.get_current_glyph ();
		
		foreach (Path p in g.path_list) {
			foreach (EditPoint ep in p.points) {
				ep.set_selected (true);
				add_selected_point (ep, p);
			}
		}
	}
	
	public static Path simplify (Path path, bool selected_segments = false, double threshold = 0.3) {
		PointSelection ps;
		EditPoint ep;
		Path p1, new_path;
		double d, sumd;
		int i;

		p1 = path.copy ();
		new_path = p1.copy ();
		i = 0;
		sumd = 0;
		while (i < new_path.points.size) {
			ep = new_path.points.get (i);
			ps = new PointSelection (ep, new_path); 
			d = PenTool.remove_point_simplify (ps);
			sumd += d;
			
			if (sumd < threshold) {
				p1 = new_path.copy ();
			} else {
				new_path = p1.copy ();
				sumd = 0;
				i++;
			}
		}
		
		new_path.update_region_boundaries ();
		
		return new_path;
	}
	
	public void set_simplification_threshold (double t) {
		simplification_threshold = t;
	}
}

}
