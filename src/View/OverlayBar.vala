/***
    Copyright (c) 2012 ammonkey <am.monkeyd@gmail.com>
                  2015-2016 elementary LLC (http://launchpad.net/elementary)

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

***/

namespace Marlin.View {

    public class OverlayBar : Granite.Widgets.OverlayBar {
        const int IMAGE_LOADER_BUFFER_SIZE = 8192;
        const int STATUS_UPDATE_DELAY = 200;
        Cancellable? cancellable = null;
        bool image_size_loaded = false;
        private uint folders_count = 0;
        private uint files_count = 0;
        private uint64 files_size = 0;
        private GOF.File? goffile = null;
        private GLib.List<unowned GOF.File>? selected_files = null;
        private uint8 [] buffer;
        private GLib.FileInputStream? stream;
        private Gdk.PixbufLoader loader;
        private uint update_timeout_id = 0;
        private Marlin.DeepCount? deep_counter = null;
        private uint deep_count_timeout_id = 0;
        private Gtk.Spinner spinner;

        public bool showbar = false;

        public OverlayBar (Marlin.View.Window win, Gtk.Overlay overlay) {
            base (overlay); /* this adds the overlaybar to the overlay (ViewContainer) */

            buffer = new uint8[IMAGE_LOADER_BUFFER_SIZE];
            status = "";
            /* Swap existing child for a Box so we can add additional widget (spinner) */
            var widget = this.get_child ();
            ((Gtk.Container)this).remove (widget);
            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            this.add (hbox);
            /* Put the existing child back */
            hbox.pack_start (widget, true, true);
            /* Now we can add a spinner */
            spinner = new Gtk.Spinner ();
            hbox.pack_start (spinner, true, true);

            hide.connect (cancel);
        }

        ~OverlayBar () {
            cancel ();
        }

        public override void get_preferred_width (out int minimum_width, out int natural_width) {
            base.get_preferred_width (out minimum_width, out natural_width);
            /* If visible, allow extra space for the spinner - the parent only allows for the label */
            if (spinner.is_visible ()) {
                Gtk.Requisition spinner_min_size, spinner_natural_size;
                spinner.get_preferred_size (out spinner_min_size, out spinner_natural_size);
                minimum_width += spinner_min_size.width;
                natural_width += spinner_natural_size.width;
            }
        }

        public void selection_changed (GLib.List<GOF.File> files) {
            cancel ();
            visible = false;

            if (!showbar)
                return;

            update_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, STATUS_UPDATE_DELAY, () => {
                if (files != null)
                    selected_files = files.copy ();
                else
                    selected_files = null;

                real_update (selected_files);
                update_timeout_id = 0;
                return false;
            });
        }

        public void reset_selection () {
            selected_files = null;
        }

        public void update_hovered (GOF.File? file) {
            cancel (); /* This will stop and hide spinner */

            if (!showbar)
                return;

            update_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, STATUS_UPDATE_DELAY, () => {
                GLib.List<GOF.File> list = null;
                if (file != null) {
                    bool matched = false;
                    if (selected_files != null) {
                        selected_files.@foreach ((f) => {
                            if (f == file)
                                matched = true;
                        });
                    }

                    if (matched)
                        real_update (selected_files);
                    else {
                        list.prepend (file);
                        real_update (list);
                    }
                } else {
                    real_update (null);
                }

                update_timeout_id = 0;
                return false;
            });
        }

        public void cancel() {
            if (update_timeout_id > 0) {
                GLib.Source.remove (update_timeout_id);
                update_timeout_id = 0;
            }

            if (deep_count_timeout_id > 0) {
                GLib.Source.remove (deep_count_timeout_id);
                deep_count_timeout_id = 0;
            }

            cancel_cancellable ();
            hide_spinner ();
        }

        private void cancel_cancellable () {
            /* if we're still collecting image info or deep counting, cancel */
            if (cancellable != null) {
                cancellable.cancel ();
            }
        }

       private void real_update (GLib.List<GOF.File>? files) {
            goffile = null;
            folders_count = 0;
            files_count = 0;
            files_size = 0;
            status = "";

            if (files != null) {
                if (files.data != null) {
                    if (files.next == null)
                        /* list contain only one element */
                        goffile = files.first ().data;
                    else
                        scan_list (files);

                    /* There is a race between load_resolution and file_real_size for setting status.
                     * On first hover, file_real_size wins.  On second hover load_resolution
                     * wins because we remembered the resolution. So only set status with string returned by
                     * update status if it has not already been set by load resolution.*/
                    var s = update_status ();
                    if (status == "") {
                        status = s;
                    }
                }
            }

            visible = showbar && (status.length > 0);
        }

        private string update_status () {
            string str = "";
            status = "";
            if (goffile != null) { /* a single file is hovered or selected */
                if (goffile.is_network_uri_scheme () || goffile.is_root_network_folder ()) {
                    str = goffile.get_display_target_uri ();
                } else if (!goffile.is_folder ()) {
                    /* if we have an image, see if we can get its resolution */
                    string? type = goffile.get_ftype ();

                    if (goffile.format_size == "" ) { /* No need to keep recalculating it */
                        goffile.format_size = format_size (PropertiesWindow.file_real_size (goffile));
                    }
                    str = "%s- %s (%s)".printf (goffile.info.get_name (),
                                                goffile.formated_type,
                                                goffile.format_size);

                    if (type != null && type.substring (0, 6) == "image/" &&     /* file is image and */
                        (goffile.width > 0 ||                                     /* resolution already determined  or*/
                        !((type in Marlin.SKIP_IMAGES) || goffile.width < 0))) { /* resolution can be determined. */

                        load_resolution.begin (goffile);
                    }
                } else {
                    str = "%s - %s".printf (goffile.info.get_name (), goffile.formated_type);
                    schedule_deep_count ();
                }
            } else { /* hovering over multiple selection */
                if (folders_count > 1) {
                    str = _("%u folders").printf (folders_count);
                    if (files_count > 0)
                        str += ngettext (_(" and %u other item (%s) selected").printf (files_count, format_size (files_size)),
                                         _(" and %u other items (%s) selected").printf (files_count, format_size (files_size)),
                                         files_count);
                    else
                        str += _(" selected");
                } else if (folders_count == 1) {
                    str = _("%u folder").printf (folders_count);
                    if (files_count > 0)
                        str += ngettext (_(" and %u other item (%s) selected").printf (files_count, format_size (files_size)),
                                         _(" and %u other items (%s) selected").printf (files_count, format_size (files_size)),
                                         files_count);
                    else
                        str += _(" selected");
                } else /* folder_count = 0 and files_count > 0 */
                    str = _("%u items selected (%s)").printf (files_count, format_size (files_size));
            }

            return str;
        }

        private void schedule_deep_count () {
            cancel ();
            /* Show the spinner immediately to indicate that something will happen if hover long enough */
            show_spinner ();

            deep_count_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, 1000, () => {
                deep_counter = new Marlin.DeepCount (goffile.location);
                deep_counter.finished.connect (update_status_after_deep_count);

                cancel_cancellable ();
                cancellable = new Cancellable ();
                cancellable.cancelled.connect (() => {
                    if (deep_counter != null) {
                        deep_counter.finished.disconnect (update_status_after_deep_count);
                        deep_counter.cancel ();
                        deep_counter = null;
                        cancellable = null;
                    }
                    hide_spinner ();
                });
                deep_count_timeout_id = 0;
                return false;
            });
        }

        private void update_status_after_deep_count () {
            string str;
            cancellable = null;
            hide_spinner ();

            status = "%s - %s (".printf (goffile.info.get_name (), goffile.formated_type);

            if (deep_counter != null) {
                if (deep_counter.dirs_count > 0) {
                    str = ngettext (_("%u sub-folder, "), _("%u sub-folders, "), deep_counter.dirs_count);
                    status += str.printf (deep_counter.dirs_count);
                }

                if (deep_counter.files_count > 0) {
                    str = ngettext (_("%u file, "), _("%u files, "), deep_counter.files_count);
                    status += str.printf (deep_counter.files_count);
                }

                if (deep_counter.total_size == 0) {
                    status += _("unknown size");
                } else {
                    status += format_size (deep_counter.total_size);
                }

                if (deep_counter.file_not_read > 0) {
                    if (deep_counter.total_size > 0) {
                        status += " approx - %u files not readable".printf (deep_counter.file_not_read);
                    } else {
                        status += " %u files not readable".printf (deep_counter.file_not_read);
                    }
                }
            }

            status += ")";
        }

        private void scan_list (GLib.List<GOF.File>? files) {
            if (files == null)
                return;

            foreach (var gof in files) {
                if (gof != null && gof is GOF.File) {
                    if (gof.is_folder ()) {
                        folders_count++;
                    } else {
                        files_count++;
                        files_size += PropertiesWindow.file_real_size (gof);
                    }
                } else {
                    warning ("Null file found in OverlayBar scan_list - this should not happen");
                }
            }
        }

        /* code is mostly ported from nautilus' src/nautilus-image-properties.c */
        private async void load_resolution (GOF.File goffile) {
            if (goffile.width > 0) { /* resolution may already have been determined */
                on_size_prepared (goffile.width, goffile.height);
                return;
            }

            var file = goffile.location;
            image_size_loaded = false;

            try {
                stream = yield file.read_async (0, cancellable);
                if (stream == null) {
                    error ("Could not read image file's size data");
                }

                loader = new Gdk.PixbufLoader.with_mime_type (goffile.get_ftype ());
                loader.size_prepared.connect (on_size_prepared);

                cancel_cancellable ();
                cancellable = new Cancellable ();

                yield read_image_stream (loader, stream, cancellable);
            } catch (Error e) {
                warning ("Error loading image resolution in OverlayBar: %s", e.message);
            }
            /* Gdk wants us to always close the loader, so we are nice to it */
            try {
                stream.close ();
            } catch (GLib.Error e) {
                debug ("Error closing stream in load resolution: %s", e.message);
            }
            try {
                loader.close ();
            } catch (GLib.Error e) { /* Errors expected because may not load whole image */
                debug ("Error closing loader in load resolution: %s", e.message);
            }
            cancellable = null;
        }

        private void on_size_prepared (int width, int height) {
            image_size_loaded = true;
            goffile.width = width;
            goffile.height = height;
            status = "%s (%s — %i × %i)".printf (goffile.formated_type, goffile.format_size, width, height);
        }

        private async void read_image_stream (Gdk.PixbufLoader loader, FileInputStream stream, Cancellable cancellable)
        {
            ssize_t read = 1;
            uint count = 0;
            while (!image_size_loaded  && read > 0 && !cancellable.is_cancelled ()) {
                try {
                    read = yield stream.read_async (buffer, 0, cancellable);
                    count++;
                    if (count > 100) {
                        goffile.width = -1; /* Flag that resolution is not determinable so do not try again*/
                        goffile.height = -1;
                        /* Note that Gdk.PixbufLoader seems to leak memory with some file types. Any file type that
                         * causes this error should be added to Marlin.SKIP_IMAGES array */
                        critical ("Could not determine resolution of file type %s", goffile.get_ftype ());
                        break;
                    }
                    loader.write (buffer);

                } catch (IOError e) {
                    if (!(e is IOError.CANCELLED))
                        warning (e.message);
                } catch (Gdk.PixbufError e) {
                    /* errors while loading are expected, we only need to know the size */
                } catch (FileError e) {
                    warning (e.message);
                } catch (Error e) {
                    warning (e.message);
                }
            }
        }

        private void show_spinner () {
            spinner.show ();
            spinner.start ();
        }

        private void hide_spinner () {
            spinner.stop ();
            spinner.hide ();
        }
    }
}
