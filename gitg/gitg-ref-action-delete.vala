/*
 * This file is part of gitg
 *
 * Copyright (C) 2014 - Jesse van den Kieboom
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

class RefActionDelete : GitgExt.Action, GitgExt.RefAction, Object
{
	// Do this to pull in config.h before glib.h (for gettext...)
	private const string version = Gitg.Config.VERSION;

	public GitgExt.RefActionInterface action_interface { get; construct set; }
	public Gitg.Ref reference { get; construct set; }

	public RefActionDelete(GitgExt.RefActionInterface action_interface, Gitg.Ref reference)
	{
		Object(action_interface: action_interface, reference: reference);
	}

	public string label
	{
		get { return _("Delete"); }
	}

	public bool enabled
	{
		get
		{
			return    reference.is_branch()
			       || reference.is_tag()
			       || reference.is_remote();
		}
	}

	public bool visible
	{
		get { return true; }
	}

	public void activated()
	{
		var query = new GitgExt.UserQuery();

		var name = reference.get_shorthand();

		if (reference.is_branch())
		{
			query.title = (_("Delete branch %s")).printf(name);
			query.message = (_("Are you sure that you want to permanently delete the branch %s?")).printf(name);
		}
		else if (reference.is_tag())
		{
			query.title = (_("Delete tag %s")).printf(name);
			query.message = (_("Are you sure that you want to permanently delete the tag %s?")).printf(name);
		}
		else
		{
			query.title = (_("Delete remote branch %s")).printf(name);
			query.message = (_("Are you sure that you want to permanently delete the remote branch %s?")).printf(name);
		}

		query.responses = new GitgExt.UserQueryResponse[] {
			new GitgExt.UserQueryResponse(_("Delete"), Gtk.ResponseType.OK),
			new GitgExt.UserQueryResponse(_("Cancel"), Gtk.ResponseType.CANCEL)
		};

		query.default_response = Gtk.ResponseType.OK;
		query.response.connect(on_response);

		action_interface.application.user_query(query);
	}

	private void on_response(Gtk.ResponseType response)
	{
		if (response != Gtk.ResponseType.OK)
		{
			return;
		}

		if (reference.is_remote())
		{
			// TODO
			return;
		}
		else
		{
			try
			{
				reference.delete();
			}
			catch (Error e)
			{
				string title;
				string message;

				var name = reference.get_shorthand();

				if (reference.is_tag())
				{
					// Translators: %s is the name of the tag
					title = _("Failed to delete tag %s").printf(name);

					// Translators: the first %s is the name of the tag, the second is an error message
					message = _("The tag %s could not be deleted: %s").printf(name, e.message);
				}
				else
				{
					// Translators: %s is the name of the branch
					title = _("Failed to delete branch %s").printf(name);

					// Translators: the first %s is the name of the branch, the second is an error message
					message = _("The branch %s could not be deleted: %s").printf(name, e.message);
				}

				action_interface.application.show_infobar(title,
				                                          message,
				                                          Gtk.MessageType.ERROR);

				return;
			}
		}

		action_interface.remove_ref(reference);
	}
}

}

// ex:set ts=4 noet
