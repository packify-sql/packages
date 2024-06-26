/*
 * 3-create-database.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-26
 * Updated: 2024-06-26
 *
 * Creates the Packify database using the name that was provided
 *
 */

USE [master];

/* Create the database using the provided escaped name */
EXECUTE AS USER = 'PackifyUser'

    EXEC sp_executesql
        N'
        CREATE DATABASE
            :database_escaped;
        ';

REVERT

DECLARE @databaseId INT = (
    SELECT
        [database_id]
    FROM
        sys.databases
    WHERE
        [name] = ':database_unescaped'
);

PRINT CONCAT(
    'Created database :database_escaped with database ID ',
    @databaseID
);

/* Make the packify login the owner of the new database */
ALTER AUTHORIZATION ON
    DATABASE:::database_escaped
TO
    [PackifyLogin];


USE :database_escaped;

EXEC sp_addrolemember
    'db_owner',
    'PackifyLogin';

PRINT 'Make PackifyLogin owner of :database_escaped database';
