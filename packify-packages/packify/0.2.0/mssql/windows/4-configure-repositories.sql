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

----------------------------------------------------------------------------------------------------
DECLARE
    @DefaultRepoName                NVARCHAR(200) = 'Packify Package Repository (Official)',
    @DefaultRepoPath                NVARCHAR(200) = 'packify-sql/packages',
    @DefaultRepoBranch              NVARCHAR(200) = 'main',
    @DefaultRepoRawContentURLFormat NVARCHAR(200) = (
        'https://raw.githubusercontent.com/:repo/:branch/:packageDir'
    ),
    @DefaultRepoListingURLFormat    NVARCHAR(200) = (
        'https://api.github.com/repos/:repo/git/trees/:branch?recursive=1'
    );
----------------------------------------------------------------------------------------------------

USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'

    /* Create a schema for repository resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Remote];';
    
    PRINT 'Created [Remote] schema';

    /* Create the repositories table and register the official repository */
    CREATE TABLE Remote.Repositories (
        [RepositoryID]          INT PRIMARY KEY IDENTITY(1,1),
        [Name]                  NVARCHAR(800) NOT NULL,
        [GitRepository]         NVARCHAR(800) NOT NULL,
        [Branch]                NVARCHAR(800) NOT NULL,
        [RawContentURLFormat]   NVARCHAR(800) NOT NULL,
        [ListingURLFormat]      NVARCHAR(800) NOT NULL,
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
        @DefaultRepoName,
        @DefaultRepoPath,
        @DefaultRepoBranch,
        @DefaultRepoRawContentURLFormat,
        @DefaultRepoListingURLFormat
    );

    PRINT 'Created the Remote.Repositories table and registered the default repository';

    /* Create tables for package caches */
    CREATE TABLE Remote.PackageCaches (
        [PackageCacheID]        BIGINT PRIMARY KEY IDENTITY(1,1),
        [RepositoryID]          INT NOT NULL,
        [CreateDateTime]        DATETIME NOT NULL DEFAULT (GETDATE()),
        [ValidUntil]            DATETIME NOT NULL,

        CONSTRAINT
            FK_Remote_PackageCaches_RepositoryID
        FOREIGN KEY (
            [RepositoryID]
        )
        REFERENCES Remote.Repositories (
            [RepositoryID]
        )
        ON DELETE CASCADE,

        CONSTRAINT
            AK_Remote_PackageCaches_RepositoryID
        UNIQUE (
            [RepositoryID]
        )
    );

    CREATE TABLE Remote.RepositoryPackages (
        [RepositoryPackageID]   BIGINT PRIMARY KEY IDENTITY(1,1),
        [PackageCacheID]        BIGINT NOT NULL,
        [PackageName]           NVARCHAR(200) NOT NULL,
        [VersionString]         NVARCHAR(200) NOT NULL,
        [CreateDateTime]        DATETIME NOT NULL DEFAULT (GETDATE()),

        CONSTRAINT
            FK_Remote_RepositoryPackages_PackageCacheID
        FOREIGN KEY (
            [PackageCacheID]
        )
        REFERENCES Remote.PackageCaches (
            [PackageCacheID]
        )
        ON DELETE CASCADE,

        CONSTRAINT
            AK_Remote_RepositoryPackages_PackageCacheIDPackageNameVersionString
        UNIQUE (
            [PackageCacheID],
            [PackageName],
            [VersionString]
        )
    );

    PRINT 'Created Remote.PackageCaches and Remote.RepositoryPackages tables';

REVERT