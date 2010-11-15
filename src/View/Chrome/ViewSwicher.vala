//  
//  ViewSwicher.cs
//  
//  Author:
//       mathijshenquet <mathijs.henquet@gmail.com>
// 
//  Copyright (c) 2010 mathijshenquet
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.


using Gtk;
using Marlin.View;
using Config;

namespace Marlin.View.Chrome
{
	public class ViewSwitcher : ToolItem
	{
		public ModeButton switcher;
		public signal void viewmode_changed(ViewMode mode);

        private ViewMode _mode;
        public ViewMode mode{
            set{
                stdout.printf("Setting Mode\n");

                Widget target;

                if(value == ViewMode.LIST){
				    target = list;
			    }else if(value == ViewMode.MILLER){
				    target = miller;
			    }else{
                    target = miller;
                }

                switcher.focus(target);
                _mode = mode;
            }
            private get{
                return _mode;
            }
        }

        private Image list;
        private Image miller;
		
		//Gdk.Pixbuf iconviewIcon = DrawingService.GetIcon("view-list-icons-symbolic;;view-list-icons", 16);
		//Gdk.Pixbuf detailsviewIcon = DrawingService.GetIcon("view-list-details-symbolic;;view-list-details", 16);
		//Gdk.Pixbuf compactviewIcon = DrawingService.GetIcon("view-list-compact-symbolic;;view-list-compact", 16);
		
		public ViewSwitcher ()
		{
			border_width = 6;
			
			switcher = new ModeButton();
		
			list = new Image.from_file(Config.PIXMAP_DIR + "view-list-details-symbolic.svg");
			switcher.append(list);
			miller = new Image.from_file(Config.PIXMAP_DIR + "view-list-column-symbolic.svg");
			switcher.append(miller);
			
			switcher.mode_changed.connect((mode) => {
				//You cannot do a switch here, only for int and string
				if(mode == list){
					viewmode_changed(ViewMode.LIST);
				}else if(mode == miller){
					viewmode_changed(ViewMode.MILLER);
				}
			});
			
			switcher.sensitive = true;
            mode = ViewMode.LIST;
			
			add (switcher);
		}
	}
}

