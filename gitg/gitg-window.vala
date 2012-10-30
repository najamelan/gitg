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

namespace Gitg
{

public class Window : Gtk.ApplicationWindow, GitgExt.Application, Initable, Gtk.Buildable
{
	private enum ViewType
	{
		DASH = 0,
		REPOSITORY = 1
	}

	private Repository? d_repository;
	private GitgExt.MessageBus d_message_bus;
	private string? d_action;

	private UIElements<GitgExt.View> d_views;
	private UIElements<GitgExt.Panel> d_panels;

	private Gtk.Notebook d_notebook;
	private GitgGtk.DashView d_dash_view;

	private Gtk.MenuButton d_config;

	// Widgets
	private Gtk.Toolbar d_toolbar_views;
	private Gtk.Toolbar d_toolbar_panels;

	private Gtk.Paned d_paned_views;
	private Gtk.Paned d_paned_panels;

	private Gtk.Frame d_frame_view;
	private Gtk.Frame d_frame_panel;

	private GitgExt.NavigationTreeView d_navigation;

	public GitgExt.View? current_view
	{
		owned get { return d_views.current; }
	}

	public GitgExt.MessageBus message_bus
	{
		owned get { return d_message_bus; }
	}

	[Notify]
	public Repository? repository
	{
		owned get { return d_repository; }
		set
		{
			close();
			d_repository = value;

			repository_changed();
		}
	}

	private void repository_changed()
	{
		d_views.update();
		activate_default_view();
	}

	private void parser_finished(Gtk.Builder builder)
	{
		// Extract widgets from the builder
		d_notebook = builder.get_object("notebook") as Gtk.Notebook;

		d_toolbar_views = builder.get_object("toolbar_views") as Gtk.Toolbar;
		d_paned_views = builder.get_object("paned_views") as Gtk.Paned;

		d_toolbar_panels = builder.get_object("toolbar_panels") as Gtk.Toolbar;
		d_paned_panels = builder.get_object("paned_panels") as Gtk.Paned;

		d_frame_view = builder.get_object("frame_view") as Gtk.Frame;
		d_frame_panel = builder.get_object("frame_panel") as Gtk.Frame;

		d_navigation = builder.get_object("tree_view_navigation") as GitgExt.NavigationTreeView;
		d_config = builder.get_object("button_config") as Gtk.MenuButton;

		d_dash_view = builder.get_object("dash_view") as GitgGtk.DashView;
		d_dash_view.repository_activated.connect((repository) => {
			this.repository = repository;
		});

		var model = Resource.load_object<MenuModel>("ui/gitg-menus.ui", "win-menu");
		d_config.menu_model = model;

		base.parser_finished(builder);
	}

	private void on_view_activated(UIElements elements,
	                               GitgExt.UIElement element)
	{
		GitgExt.View? view = (GitgExt.View?)element;

		// 1) Clear the navigation tree
		d_navigation.model.clear();

		if (view != null)
		{
			// 2) Populate the navigation tree for this view
			d_navigation.model.populate(view.navigation);
			d_navigation.expand_all();

			d_navigation.select_first();
		}

		// Update panels
		d_panels.update();
		notify_property("current_view");
	}

	private void on_panel_activated(UIElements elements,
	                                GitgExt.UIElement element)
	{
	}

	private void activate_default_view()
	{
		if (d_repository == null)
		{
			d_notebook.set_current_page(ViewType.DASH);
		}
		else
		{
			d_notebook.set_current_page(ViewType.REPOSITORY);

			d_views.foreach((element) => {
				GitgExt.View view = (GitgExt.View)element;

				if (view.is_default_for(d_action != null ? d_action : ""))
				{
					if (d_views.current == view)
					{
						on_view_activated(d_views, view);
					}
					else
					{
						d_views.current = view;
					}

					return false;
				}

				return true;
			});
		}
	}

	private bool init(Cancellable? cancellable)
	{
		// Setup message bus
		d_message_bus = new GitgExt.MessageBus();

		// Initialize peas extensions set for views
		var engine = PluginsEngine.get_default();

		d_views = new UIElements<GitgExt.View>(new Peas.ExtensionSet(engine,
		                                                            typeof(GitgExt.View),
		                                                            "application",
		                                                            this),
		                                       d_frame_view,
		                                       d_toolbar_views);

		d_views.activated.connect(on_view_activated);

		d_panels = new UIElements<GitgExt.Panel>(new Peas.ExtensionSet(engine,
		                                                               typeof(GitgExt.Panel),
		                                                               "application",
		                                                               this),
		                                         d_frame_panel,
		                                         d_toolbar_panels);

		d_panels.activated.connect(on_panel_activated);

		activate_default_view();
		return true;
	}

	public static Window? create_new(Gtk.Application app,
	                                 Repository? repository,
	                                 string? action)
	{
		Window? ret = Resource.load_object<Window>("ui/gitg-window.ui", "window");

		if (ret != null)
		{
			ret.d_action = action;
			ret.d_repository = repository;
		}

		try
		{
			((Initable)ret).init(null);
		} catch {}

		ret.repository_changed();
		return ret;
	}

	/* public API implementation of GitgExt.Application */
	public GitgExt.View? view(string id)
	{
		GitgExt.View? v = d_views.lookup(id);

		if (v != null)
		{
			d_views.current = v;
		}

		if (d_views.current == v)
		{
			return v;
		}
		else
		{
			return null;
		}
	}

	public void open(File path)
	{
		File repo;
		Gitg.Repository? repository = null;

		if (d_repository != null &&
		    d_repository.get_location().equal(path))
		{
			return;
		}

		try
		{
			repo = Ggit.Repository.discover(path);
		}
		catch
		{
			// TODO: make error thingie
			return;
		}

		try
		{
			repository = new Gitg.Repository(repo, null);
		}
		catch {}

		this.repository = repository;
	}

	public void create(File path)
	{
		// TODO
	}

	public void close()
	{
		// TODO
	}
}

}

// ex:ts=4 noet
