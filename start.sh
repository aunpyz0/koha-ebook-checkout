#!/bin/sh

koha-zebra --start mylibrary
koha-indexer --start mylibrary

/usr/bin/supervisord
