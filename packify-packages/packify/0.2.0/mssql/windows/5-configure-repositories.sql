/*
 * 4-configure-repositories.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-26
 * Updated: 2024-06-26
 *
 * Creates database resources related to repositories and configures
 * the official Packify package repository as default
 *
 */

EXECUTE AS USER = 'PackifyUser'

    /* Operate against the database we created in the previous step */
    USE :database_escaped;

    /* Create a schema for repository resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Remote];';

    /* Create the repositories table and register the official repository */
    CREATE TABLE Remote.Repositories (
        [RepositoryID]          INT PRIMARY KEY IDENTITY(1,1),
        [Name]                  NVARCHAR(2000) NOT NULL,
        [GitRepository]         NVARCHAR(2000) NOT NULL,
        [Branch]                NVARCHAR(2000) NOT NULL,
        [RawContentURLFormat]   NVARCHAR(2000) NOT NULL,
        [ListingURLFormat]      NVARCHAR(2000) NOT NULL,
        [CreateDateTime]        DATETIME NOT NULL DEFAULT (GETDATE()),

        CONSTRAINT
            AK_Remote_Repositories_Name
        UNIQUE (
            [Name]
        )
    );

    INSERT INTO Remote.Repositories (
        [Name],
        [GitRepository],
        [Branch],
        [RawContentURLFormat],
        [ListingURLFormat]
    )
    VALUES (
        'Packify Package Repository (Official)',
        'packify-sql/packages',
        'main',
        'https://raw.githubusercontent.com/:repo/:branch/:packageDir',
        'https://api.github.com/repos/:repo/git/trees/:branch?recursive=1'
    );

REVERT