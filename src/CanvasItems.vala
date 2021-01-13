/*
* Copyright (c) 2020 (https://github.com/phase1geo/Annotator)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Trevor Williams <phase1geo@gmail.com>
*/

using Gtk;
using Gdk;
using Cairo;

public enum CanvasItemType {
  RECT_STROKE = 0,
  RECT_FILL,
  OVAL_STROKE,
  OVAL_FILL,
  STAR_STROKE,
  STAR_FILL,
  LINE,
  ARROW,
  TEXT,
  BLUR,
  MAGNIFIER
}

public class CanvasItems {

  private Canvas               _canvas;
  private List<CanvasItem>     _items;
  private CanvasItem?          _active         = null;
  private int                  _selector_index = -1;
  private double               _last_x;
  private double               _last_y;
  private Array<string>        _shape_icons;
  private int                  _press_count    = -1;

  public CanvasItemProperties props { get; private set; }

  public signal void text_item_edit_changed( CanvasItemText item );

  /* Constructor */
  public CanvasItems( Canvas canvas ) {

    _canvas = canvas;

    /* Create storage for the canvas items */
    _items = new List<CanvasItem>();

    /* Create the overall properties structure */
    props = new CanvasItemProperties( true );
    props.changed.connect( update_selected_attributes );

    /* Load the shapes */
    _shape_icons = new Array<string>();
    _shape_icons.append_val( "rect-stroke-symbolic" );
    _shape_icons.append_val( "rect-fill-symbolic" );
    _shape_icons.append_val( "circle-stroke-symbolic" );
    _shape_icons.append_val( "circle-fill-symbolic" );
    _shape_icons.append_val( "star-stroke-symbolic" );
    _shape_icons.append_val( "star-fill-symbolic" );
    _shape_icons.append_val( "line-symbolic" );
    _shape_icons.append_val( "arrow-symbolic" );

  }

  /* Returns the number of shapes that we support */
  public int num_shapes() {
    return( (int)_shape_icons.length );
  }

  /* Returns the shape of the icon */
  public Image get_shape_icon( int index ) {
    return( new Image.from_icon_name( _shape_icons.index( index ), IconSize.LARGE_TOOLBAR ) );
  }

  /* Returns the box to place a canvas item into */
  private CanvasRect center_box( double width, double height ) {
    var rect = _canvas.editor.get_displayed_rect();
    rect.copy_coords( (rect.x + ((rect.width - width) / 2)), (rect.y + ((rect.height - height) / 2)), width, height );
    return( rect );
  }

  private CanvasItem create_rectangle( bool fill ) {
    var item = new CanvasItemRect( fill, props );
    item.bbox = center_box( 200, 50 );
    return( item );
  }

  private CanvasItem create_oval( bool fill ) {
    var item = new CanvasItemOval( fill, props );
    item.bbox = center_box( 200, 50 );
    return( item );
  }

  private CanvasItem create_star( bool fill ) {
    var item = new CanvasItemStar( fill, 5, 25, props );
    item.bbox = center_box( 100, 100 );
    return( item );
  }

  private CanvasItem create_line() {
    var item = new CanvasItemLine( props );
    item.bbox = center_box( 200, 1 );
    return( item );
  }

  private CanvasItem create_arrow() {
    var item = new CanvasItemArrow( props );
    item.bbox = center_box( 200, 1 );
    return( item );
  }

  private CanvasItem create_text() {
    var item = new CanvasItemText( _canvas, props );
    item.bbox = center_box( 200, 1 );
    _active = item;
    set_edit_mode( true );
    return( item );
  }

  private CanvasItem create_blur() {
    var item = new CanvasItemBlur( _canvas.image, props );
    item.bbox = center_box( 200, 50 );
    return( item );
  }

  private CanvasItem create_magnifier() {
    var item = new CanvasItemMagnifier( _canvas.image, 2.0, props );
    item.bbox = center_box( 200, 200 );
    return( item );
  }

  public void add_item( CanvasItem item, int position ) {
    clear_selection();
    item.mode = CanvasItemMode.SELECTED;
    _items.insert( item, position );
  }

  /* Adds the given shape to the top of the item stack */
  public void add_shape_item( CanvasItemType type ) {
    CanvasItem? item = null;
    switch( type ) {
      case CanvasItemType.RECT_STROKE  :  item = create_rectangle( false );  break;
      case CanvasItemType.RECT_FILL    :  item = create_rectangle( true );  break;
      case CanvasItemType.OVAL_STROKE  :  item = create_oval( false );  break;
      case CanvasItemType.OVAL_FILL    :  item = create_oval( true );  break;
      case CanvasItemType.STAR_STROKE  :  item = create_star( false );  break;
      case CanvasItemType.STAR_FILL    :  item = create_star( true );  break;
      case CanvasItemType.LINE         :  item = create_line();  break;
      case CanvasItemType.ARROW        :  item = create_arrow();  break;
      case CanvasItemType.TEXT         :  item = create_text();  break;
      case CanvasItemType.BLUR         :  item = create_blur();  break;
      case CanvasItemType.MAGNIFIER    :  item = create_magnifier();  break;
      default :  assert_not_reached();
    }
    add_item( item, -1 );
    _canvas.undo_buffer.add_item( new UndoItemAdd( item, (int)(_items.length() - 1) ) );
    _canvas.queue_draw();
  }

  /* Removes all of the canvas items */
  private void clear() {
    while( _items.first() != null ) {
      _items.delete_link( _items.first() );
    }
    _canvas.queue_draw();
  }

  /* Removes the item at the given position */
  public void remove_item( CanvasItem item ) {
    _items.remove( item );
  }

  /* Deletes all of the selected items */
  private bool remove_selected() {
    var retval    = false;
    var position  = 0;
    var undo_item = new UndoItemDelete();
    for( unowned List<CanvasItem> item=_items.first(); item!=null; item=item.next ) {
      if( item.data.mode == CanvasItemMode.SELECTED ) {
        undo_item.add( item.data, position );
        _items.delete_link( item );
        _canvas.set_cursor( null );
        retval = true;
      }
      position++;
    }
    if( retval ) {
      _canvas.undo_buffer.add_item( undo_item );
    }
    return( retval );
  }

  /* Clears the currently selected items */
  public void clear_selection() {
    _selector_index = -1;
    foreach( CanvasItem item in _items ) {
      item.mode = CanvasItemMode.NONE;
    }
  }

  /* Update the selected attributes */
  private void update_selected_attributes() {
    var undo_item = new UndoItemPropChange();
    foreach( CanvasItem item in _items ) {
      if( item.mode == CanvasItemMode.SELECTED ) {
        item.props = props;
        undo_item.add( item );
      }
    }
    if( !undo_item.empty() ) {
      _canvas.undo_buffer.replace_item( undo_item );
    }
    _canvas.queue_draw();
  }

  public void adjust_items( double diffx, double diffy ) {
    foreach( CanvasItem item in _items ) {
      item.move_item( (0 - diffx), (0 - diffy) );
    }
  }

  /* Returns true if the shift key is enabled in the given state */
  private bool shift_state( ModifierType state ) {
    return( (bool)(state & ModifierType.SHIFT_MASK) );
  }

  /* Returns true if the control key is enabled in the given state */
  private bool control_state( ModifierType state ) {
    return( (bool)(state & ModifierType.CONTROL_MASK) );
  }

  /* Returns true if the alt key is enabled in the given state */
  private bool alt_state( ModifierType state ) {
    return( (bool)(state & ModifierType.MOD1_MASK) );
  }

  /* Returns the active text item, if it is set; otherwise, returns null */
  public CanvasItemText? get_active_text() {
    return( ((_active == null) || (_active.name != "text")) ? null : (_active as CanvasItemText) );
  }

  /* Returns true if we are currently editing a text item */
  public bool in_edit_mode() {
    var text = get_active_text();
    return( (text != null) ? text.edit : false );
  }

  /* Sets the edit mode of the active text item to the given value */
  private bool set_edit_mode( bool value ) {
    var text = get_active_text();
    if( text != null ) {
      if( text.edit != value ) {
        text.edit = value;
        if( value ) {
          text.set_cursor_all( false );
        } else {
          text.clear_selection();
        }
        text_item_edit_changed( text );
        return( true );
      }
    }
    return( false );
  }

  /*****************************/
  /*  HANDLE KEY PRESS EVENTS  */
  /*****************************/

  /* Handles keypress events.  Returns true if the canvas should be redrawn. */
  public bool key_pressed( uint keyval, ModifierType state ) {

    var control = control_state( state );
    var shift   = shift_state( state );

    switch( keyval ) {
      case Key.BackSpace :  return( handle_backspace() );
      case Key.Delete    :  return( handle_delete() );
      case Key.Return    :  return( handle_return( shift ) );
      case Key.Escape    :  return( handle_escape() );
      case Key.Left      :
      case Key.Right     :
      case Key.Home      :
      case Key.End       :
      case Key.Up        :
      case Key.Down      :  return( handle_cursor( control, shift, keyval ) );
    }

    return( false );

  }

  /*
   If we editing text, handle the backspace character; otherwise, delete the selected
   items.
  */
  private bool handle_backspace() {
    if( in_edit_mode() ) {
      var text = get_active_text();
      text.backspace( _canvas.undo_text );
    } else {
      remove_selected();
    }
    return( true );
  }

  /*
   If we editing text, handle the delete character; otherwise, delete the selected
   items.
  */
  private bool handle_delete() {
    if( in_edit_mode() ) {
      var text = get_active_text();
      text.delete( _canvas.undo_text );
    } else {
      remove_selected();
    }
    return( true );
  }

  /* If we are in text editing mode, mark the node as being not in edit mode */
  private bool handle_return( bool shift ) {
    if( in_edit_mode() ) {
      if( shift ) {
        var text = get_active_text();
        text.insert( "\n", _canvas.undo_text );
      } else {
        set_edit_mode( false );
        _active.mode = CanvasItemMode.NONE;
        _active = null;
      }
      return( true );
    }
    return( false );
  }

  /* If we are in text editing mode, remove the active node from editing mode */
  private bool handle_escape() {
    if( in_edit_mode() ) {
      set_edit_mode( false );
      _active.mode = CanvasItemMode.NONE;
      _active = null;
      return( true );
    }
    return( false );
  }

  /* If we are in edit mode, moves cursor to the left/right or adds to the selection */
  private bool handle_cursor( bool control, bool shift, uint keyval ) {
    if( in_edit_mode() ) {
      var text = get_active_text();
      if( control ) {
        if( shift ) {
          switch( keyval ) {
            case Key.Left  :  text.selection_by_word( -1 );  break;
            case Key.Right :  text.selection_by_word( 1 );   break;
            case Key.Up    :  text.selection_to_start();     break;
            case Key.Down  :  text.selection_to_end();       break;
            default        :  return( false );
          }
        } else {
          switch( keyval ) {
            case Key.Left  :  text.move_cursor_by_word( -1 );  break;
            case Key.Right :  text.move_cursor_by_word( 1 );   break;
            case Key.Up    :  text.move_cursor_to_start();     break;
            case Key.Down  :  text.move_cursor_to_end();       break;
            default        :  return( false );
          }
        }
      } else {
        if( shift ) {
          switch( keyval ) {
            case Key.Left  :  text.selection_by_char( -1 );     break;
            case Key.Right :  text.selection_by_char( 1 );      break;
            case Key.Up    :  text.selection_vertically( -1 );  break;
            case Key.Down  :  text.selection_vertically( 1 );   break;
            case Key.Home  :  text.selection_to_start();        break;
            case Key.End   :  text.selection_to_end();          break;
            default        :  return( false );
          }
        } else {
          switch( keyval ) {
            case Key.Left  :  text.move_cursor( -1 );             break;
            case Key.Right :  text.move_cursor( 1 );              break;
            case Key.Up    :  text.move_cursor_vertically( -1 );  break;
            case Key.Down  :  text.move_cursor_vertically( 1 );   break;
            case Key.Home  :  text.move_cursor_to_start();        break;
            case Key.End   :  text.move_cursor_to_end();          break;
            default        :  return( false );
          }
        }
      }
      return( true );
    }
    return( false );
  }

  /*****************************/
  /*  HANDLE MOUSE EVENTS  */
  /*****************************/

  /*
   Called whenever the cursor is pressed.  Returns true if the canvas should
   draw itself.
  */
  public bool cursor_pressed( double x, double y, ModifierType state, int press_count ) {

    var retval = false;

    /* Keep track of the press count */
    _press_count = press_count;

    /* Reverse the list so that we grab the top-most item */
    _items.reverse();

    foreach( CanvasItem item in _items ) {
      _selector_index = item.is_within_selector( x, y );
      if( _selector_index != -1 ) {
        _active = item;
        _active.mode = CanvasItemMode.RESIZING;
        _items.reverse();
        return( false );
      }
      if( item.is_within( x, y ) ) {
        _active = item;
        if( _active.mode == CanvasItemMode.NONE ) {
          clear_selection();
        }
        if( in_edit_mode() ) {
          var text = get_active_text();
          switch( press_count ) {
            case 1 :  text.set_cursor_at_char( x, y, false );  break;
            case 2 :  text.set_cursor_at_word( x, y, false );  break;
            case 3 :  text.set_cursor_all( false );            break;
          }
        } else {
          switch( press_count ) {
            case 1 :
              _active.mode = CanvasItemMode.SELECTED;
              _canvas.set_cursor_from_name( "grabbing" );
              break;
            case 2 :
              if( _active.name != "text" ) return( false );
              set_edit_mode( true );
              break;
          }
        }
        _items.reverse();
        return( true );
      }
    }

    /* Return the list order */
    _items.reverse();

    /* If we didn't click on anything, clear the selection */
    clear_selection();

    /* Clear the edit mode, if we are in it */
    retval = set_edit_mode( false );

    /* Clear the active indicator */
    _active = null;

    return( retval );

  }

  /*
   Called whenever the cursor is moved.  Returns true if the canvas should draw
   itself.
  */
  public bool cursor_moved( double x, double y, ModifierType state ) {

    var diff_x = x - _last_x;
    var diff_y = y - _last_y;
    var shift  = shift_state( state );

    _last_x = x;
    _last_y = y;

    /* Since we pressed on a selector, move the selector */
    if( _selector_index != -1 ) {
      _active.move_selector( _selector_index, diff_x, diff_y, shift );
      return( true );

    /* If we are in edit mode, drag out the selection */
    } else if( in_edit_mode() ) {
      var text = get_active_text();
      switch( _press_count ) {
        case 1  :  text.set_cursor_at_char( x, y, true );  break;
        case 2  :  text.set_cursor_at_word( x, y, true );  break;
        default :  return( false );
      }
      return( true );

    /* Otherwise, move any selected items by the given amount */
    } else if( (_active != null) && !in_edit_mode() ) {
      var retval    = false;
      foreach( CanvasItem item in _items ) {
        if( item.mode.can_move() ) {
          item.move_item( diff_x, diff_y );
          retval = true;
        }
      }
      return( retval );

    /* Otherwise, we are just moving the cursor around the screen */
    } else {
      foreach( CanvasItem item in _items ) {
        if( item.mode == CanvasItemMode.SELECTED ) {
          var sel_index = item.is_within_selector( x, y );
          if( sel_index != -1 ) {
            _canvas.set_cursor( item.get_selector_cursor( sel_index ) );
            return( false );
          }
        }
      }
      foreach( CanvasItem item in _items ) {
        if( item.is_within( x, y ) ) {
          _canvas.set_cursor( CursorType.HAND1 );
          return( false );
        }
      }
      _canvas.set_cursor( null );
    }

    return( false );

  }

  /*
   Called whenever the cursor button is released.  Returns true if the canvas
   should draw itself.
  */
  public bool cursor_released( double x, double y, ModifierType state ) {

    var retval = false;

    _press_count = -1;

    /* If we are finished dragging the selector, clear it */
    if( _selector_index != -1 ) {
      _canvas.undo_buffer.add_item( new UndoItemBoxChange.with_item( _( "resize item" ), _active ) );
      _selector_index = -1;
      _active.mode    = CanvasItemMode.SELECTED;
      _active         = null;
      retval = true;

    /* If we are editing text, do nothing */
    } else if( in_edit_mode() ) {
      return( true );

    /* If we were move one or more items, make sure that they stay selected */
    } else if( _active != null ) {
      var undo_item = new UndoItemBoxChange( _( "move items" ) );
      foreach( CanvasItem item in _items ) {
        if( item.mode == CanvasItemMode.MOVING ) {
          undo_item.add( item );
          item.mode = CanvasItemMode.SELECTED;
          retval = true;
        }
      }
      if( retval ) {
        _canvas.undo_buffer.add_item( undo_item );
      }

    /* If we have not clicked/moved anything important, clear the selection */
    } else if( _active == null ) {
      clear_selection();
      retval = true;
    }

    /* Clear the active element */
    _active = null;

    /* Clear the cursor */
    _canvas.set_cursor( null );

    /* Make sure that the canvas has input focus */
    _canvas.grab_focus();

    return( retval );

  }

  public Xml.Node* save() {
    Xml.Node* node = new Xml.Node( null, "items" );
    foreach( CanvasItem item in _items ) {
      node->add_child( item.save() );
    }
    return( node );
  }

  public void load( Xml.Node* node ) {
    for( Xml.Node* it=node->children; it!=null; it=it->next ) {
      if( it->type == Xml.ElementType.ELEMENT_NODE ) {
        CanvasItem? item = null;
        switch( it->name ) {
          case "rectangle" :  item = create_rectangle( true );  break;
          case "oval"      :  item = create_oval( true );  break;
          case "star"      :  item = create_star( true );  break;
          case "line"      :  item = create_line();  break;
          case "arrow"     :  item = create_arrow();  break;
          case "text"      :  item = create_text();  break;
        }
        if( item != null ) {
          item.load( it );
          _items.append( item );
        }
      }
    }
  }

  /* Draws all of the canvas items on the given context */
  public void draw( Context ctx ) {
    foreach( CanvasItem item in _items ) {
      item.draw_item( ctx );
    }
    foreach( CanvasItem item in _items ) {
      item.draw_selectors( ctx );
    }
  }

}


