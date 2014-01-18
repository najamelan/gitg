/*
 * This file is part of gitg
 *
 * Copyright (C) 2012 - Jesse van den Kieboom
 *
 * gitg is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * gitg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with gitg. If not, see <http://www.gnu.org/licenses/>.
 */

namespace GitgHistory
{
	/* The main history view. This view shows the equivalent of git log, but
	 * in a nice way with lanes, merges, ref labels etc.
	 */
	public class Activity : Object, GitgExt.UIElement, GitgExt.Activity, GitgExt.History
	{
		// Do this to pull in config.h before glib.h (for gettext...)
		private const string version = Gitg.Config.VERSION;

		public GitgExt.Application? application { owned get; construct set; }

		private Gitg.CommitModel? d_commit_list_model;

		private Gee.HashSet<Ggit.OId> d_selected;
		private ulong d_insertsig;
		private Settings d_settings;

		private Paned d_main;

		private Gitg.UIElements<GitgExt.HistoryPanel> d_panels;

		public Activity(GitgExt.Application application)
		{
			Object(application: application);
		}

		public string id
		{
			owned get { return "/org/gnome/gitg/Activities/History"; }
		}

		public void foreach_selected(GitgExt.ForeachCommitSelectionFunc func)
		{
			bool breakit = false;

			d_main.commit_list_view.get_selection().selected_foreach((model, path, iter) => {
				if (!breakit)
				{
					var c = d_commit_list_model.commit_from_iter(iter);

					if (c != null)
					{
						breakit = !func(c);
					}
				}
			});
		}

		construct
		{
			d_settings = new Settings("org.gnome.gitg.preferences.history");
			d_settings.changed["topological-order"].connect((s, k) => {
				update_sort_mode();
			});

			d_selected = new Gee.HashSet<Ggit.OId>((Gee.HashDataFunc<Ggit.OId>)Ggit.OId.hash,
			                                       (Gee.EqualDataFunc<Ggit.OId>)Ggit.OId.equal);

			d_commit_list_model = new Gitg.CommitModel(application.repository);
			d_commit_list_model.started.connect(on_commit_model_started);
			d_commit_list_model.finished.connect(on_commit_model_finished);

			update_sort_mode();

			application.bind_property("repository", d_commit_list_model,
			                          "repository", BindingFlags.DEFAULT);
		}

		private void update_sort_mode()
		{
			if (d_settings.get_boolean("topological-order"))
			{
				d_commit_list_model.sort_mode |= Ggit.SortMode.TOPOLOGICAL;
			}
			else
			{
				d_commit_list_model.sort_mode &= ~Ggit.SortMode.TOPOLOGICAL;
			}
		}

		private void on_commit_model_started(Gitg.CommitModel model)
		{
			if (d_insertsig == 0)
			{
				d_insertsig = d_commit_list_model.row_inserted.connect(on_row_inserted_select);
			}
		}

		private void on_row_inserted_select(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter)
		{
			var commit = d_commit_list_model.commit_from_path(path);

			if (d_selected.size == 0 || d_selected.remove(commit.get_id()))
			{
				d_main.commit_list_view.get_selection().select_path(path);
			}

			if (d_selected.size == 0)
			{
				d_commit_list_model.disconnect(d_insertsig);
				d_insertsig = 0;
			}
		}

		private void on_commit_model_finished(Gitg.CommitModel model)
		{
			if (d_insertsig != 0)
			{
				d_commit_list_model.disconnect(d_insertsig);
				d_insertsig = 0;
			}
		}

		public bool available
		{
			get { return true; }
		}

		public string display_name
		{
			owned get { return _("History"); }
		}

		public string? icon
		{
			owned get { return "view-list-symbolic"; }
		}

		public Gtk.Widget? widget
		{
			owned get
			{
				if (d_main == null)
				{
					build_ui();
				}

				return d_main;
			}
		}

		public bool is_default_for(string action)
		{
			return (action == "" || action == "history");
		}

		public bool enabled
		{
			get { return true; }
		}

		public int negotiate_order(GitgExt.UIElement other)
		{
			return -1;
		}

		private void build_ui()
		{
			d_main = new Paned();

			d_main.commit_list_view.model = d_commit_list_model;

			d_main.commit_list_view.get_selection().changed.connect((sel) => {
				selection_changed();
			});

			var engine = Gitg.PluginsEngine.get_default();

			var extset = new Peas.ExtensionSet(engine,
			                                   typeof(GitgExt.HistoryPanel),
			                                   "history",
			                                   this,
			                                   "application",
			                                   application);

			d_panels = new Gitg.UIElements<GitgExt.HistoryPanel>(extset,
			                                                     d_main.stack_panel);

			d_main.refs_list.popup_menu.connect(on_refs_list_popup_menu);
			d_main.refs_list.button_press_event.connect(on_refs_list_button_press_event);

			d_main.refs_list.editing_done.connect(on_ref_edited);

			d_main.refs_list.notify["selection"].connect(() => {
				update_walker();
			});

			application.bind_property("repository", d_main.refs_list,
			                          "repository",
			                          BindingFlags.DEFAULT |
			                          BindingFlags.SYNC_CREATE);
		}

		private void on_ref_edited(Gitg.Ref reference, string new_text, bool cancelled)
		{
			if (cancelled)
			{
				return;
			}

			string orig;
			string? prefix;

			var pn = reference.parsed_name;

			if (pn.rtype == Gitg.RefType.REMOTE)
			{
				orig = pn.remote_branch;
				prefix = pn.prefix + "/" + pn.remote_name + "/";
			}
			else
			{
				orig = pn.shortname;
				prefix = pn.prefix;
			}

			if (orig == new_text)
			{
				return;
			}

			if (!Ggit.Ref.is_valid_name(@"$prefix$new_text"))
			{
				var msg = _("The specified name ‘%s’ contains invalid characters").printf(new_text);

				application.show_infobar(_("Invalid name"),
				                         msg,
				                         Gtk.MessageType.ERROR);

				return;
			}

			var branch = reference as Ggit.Branch;
			Gitg.Ref? new_ref = null;

			try
			{
				if (branch != null)
				{
					new_ref = branch.move(new_text, Ggit.CreateFlags.NONE) as Gitg.Ref;
				}
				else
				{
					new_ref = reference.rename(new_text, false) as Gitg.Ref;
				}
			}
			catch (Error e)
			{
				application.show_infobar(_("Failed to rename"),
				                         e.message,
				                         Gtk.MessageType.ERROR);

				return;
			}

			d_main.refs_list.replace_ref(reference, new_ref);
		}

		private void add_ref_action(Gee.LinkedList<GitgExt.RefAction> actions, GitgExt.RefAction? action)
		{
			if (action.visible)
			{
				actions.add(action);
			}
		}

		private bool refs_list_popup_menu(Gtk.Widget widget, Gdk.EventButton? event)
		{
			var button = (event == null ? 0 : event.button);
			var time = (event == null ? Gtk.get_current_event_time() : event.time);

			var actions = new Gee.LinkedList<GitgExt.RefAction>();
			var references = d_main.refs_list.selection;

			if (references.is_empty || references.first() != references.last())
			{
				return false;
			}

			var reference = references.first();

			var rename = new Gitg.RefActionRename(application.action_interface,
			                                      reference);

			rename.activated.connect(() => { on_rename_activated(rename); });

			add_ref_action(actions, rename);

			add_ref_action(actions,
			               new Gitg.RefActionDelete(application.action_interface,
			                                        reference));

			var exts = new Peas.ExtensionSet(Gitg.PluginsEngine.get_default(),
			                                 typeof(GitgExt.RefAction),
			                                 "action_interface",
			                                 application.action_interface,
			                                 "reference",
			                                 reference);

			exts.foreach((extset, info, extension) => {
				add_ref_action(actions, extension as GitgExt.RefAction);
			});

			if (actions.is_empty)
			{
				return false;
			}

			Gtk.Menu menu = new Gtk.Menu();

			foreach (var ac in actions)
			{
				ac.populate_menu(menu);
			}

			menu.attach_to_widget(widget, null);
			menu.popup(null, null, null, button, time);

			return true;
		}

		private void on_rename_activated(Gitg.RefActionRename action)
		{
			d_main.refs_list.begin_editing(action.reference as Gitg.Ref);
		}

		private bool on_refs_list_popup_menu(Gtk.Widget widget)
		{
			return refs_list_popup_menu(widget, null);
		}

		private bool on_refs_list_button_press_event(Gtk.Widget widget, Gdk.EventButton event)
		{
			Gdk.Event *ev = (Gdk.Event *)(&event);

			if (!ev->triggers_context_menu())
			{
				return false;
			}

			var row = d_main.refs_list.get_row_at_y((int)event.y);
			d_main.refs_list.select_row(row);

			return refs_list_popup_menu(widget, event);
		}

		private void update_walker()
		{
			d_selected.clear();

			foreach (var r in d_main.refs_list.selection)
			{
				try
				{
					var resolved = r.resolve();

					if (resolved.is_tag())
					{
						var t = application.repository.lookup<Ggit.Tag>(resolved.get_target());
						d_selected.add(t.get_target_id());
					}
					else
					{
						d_selected.add(resolved.get_target());
					}
				}
				catch {}
			}

			d_commit_list_model.set_include(d_selected.to_array());
			d_commit_list_model.reload();
		}
	}
}

// ex: ts=4 noet
