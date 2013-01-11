/******************************************************
Copyright (c) 2011 Percona Ireland Ltd.

Data sink interface.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

*******************************************************/

#include <my_base.h>
#include "common.h"
#include "datasink.h"
#include "ds_compress.h"
#include "ds_stream.h"
#include "ds_local.h"
#include "ds_tmpfile.h"

/************************************************************************
Create a datasink of the specified type */
ds_ctxt_t *
ds_create(const char *root, ds_type_t type)
{
	datasink_t	*ds;
	ds_ctxt_t	*ctxt;

	switch (type) {
	case DS_TYPE_LOCAL:
		ds = &datasink_local;
		break;
	case DS_TYPE_STREAM:
		ds = &datasink_stream;
		break;
	case DS_TYPE_COMPRESS:
		ds = &datasink_compress;
		break;
	case DS_TYPE_TMPFILE:
		ds = &datasink_tmpfile;
		break;
	default:
		msg("Unknown datasink type: %d\n", type);
		return NULL;
	}

	ctxt = ds->init(root);
	if (ctxt != NULL) {
		ctxt->datasink = ds;
	} else {
		msg("Error: failed to initialize datasink.\n");
		exit(EXIT_FAILURE);
	}

	return ctxt;
}

/************************************************************************
Open a datasink file */
ds_file_t *
ds_open(ds_ctxt_t *ctxt, const char *path, MY_STAT *stat)
{
	ds_file_t	*file;

	file = ctxt->datasink->open(ctxt, path, stat);
	if (file != NULL) {
		file->datasink = ctxt->datasink;
	}

	return file;
}

/************************************************************************
Write to a datasink file.
@return 0 on success, 1 on error. */
int
ds_write(ds_file_t *file, const void *buf, size_t len)
{
	return file->datasink->write(file, buf, len);
}

/************************************************************************
Close a datasink file.
@return 0 on success, 1, on error. */
int
ds_close(ds_file_t *file)
{
	return file->datasink->close(file);
}

/************************************************************************
Destroy a datasink handle */
void
ds_destroy(ds_ctxt_t *ctxt)
{
	ctxt->datasink->deinit(ctxt);
}

/************************************************************************
Set the destination pipe for a datasink (only makes sense for compress and
tmpfile). */
void ds_set_pipe(ds_ctxt_t *ctxt, ds_ctxt_t *pipe_ctxt)
{
	ctxt->pipe_ctxt = pipe_ctxt;
}
