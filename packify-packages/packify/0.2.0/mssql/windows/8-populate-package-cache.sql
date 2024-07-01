/*
 * 7-populate-package-cache.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-29
 * Updated: 2024-06-29
 *
 * Populates package caches for remote repositories
 *
 */

/* Operate against the database we created in the previous step */
USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'
    /* Create a schema for utility types and other resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Utils];';
    
    PRINT 'Created [Utils] schema';

    /* Create a type to represent generic parameter names and values */
    CREATE TYPE Utils.Parameters AS TABLE (
        [ParameterName]     NVARCHAR(800),
        [ParameterValue]    SQL_VARIANT
    );

    PRINT 'Created type Utils.Parameters';

    /* Create a procedure to replace target values */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Utils.ReplaceParameters
            @UrlFormat          NVARCHAR(MAX),
            @Parameters         Utils.Parameters        READONLY,
            @ResultUrl          NVARCHAR(MAX)           OUTPUT
        WITH EXECUTE AS OWNER AS BEGIN
            SET @ResultUrl = @UrlFormat;

            /* Cursor over all of the parameters */
            DECLARE paramCursor CURSOR FOR
            SELECT
                [ParameterName],
                [ParameterValue]
            FROM
                @Parameters;
            
            DECLARE
                @parameterName      NVARCHAR(800),
                @parameterValue     SQL_VARIANT;
            
            OPEN paramCursor;

            FETCH NEXT FROM
                paramCursor
            INTO
                @parameterName,
                @parameterValue;
            
            WHILE @@FETCH_STATUS = 0 BEGIN
                SET @ResultUrl = REPLACE(
                    @ResultUrl,
                    CONCAT('':'', @parameterName),
                    CAST(@parameterValue AS NVARCHAR(MAX))
                );

                FETCH NEXT FROM
                    paramCursor
                INTO
                    @parameterName,
                    @parameterValue;
            END
        END
        ';
    
    PRINT 'Created procedure Utils.ReplaceParameters';
    
    /* Create a procedure that can parse out a package name from a package.json path */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Remote.PackageNameFromJsonPath (
            @JsonPath           NVARCHAR(MAX),
            @PackagesDir        NVARCHAR(800)   = ''packify-packages'',
            @PackageJsonFile    NVARCHAR(800)   = ''package.json''
        ) RETURNS NVARCHAR(MAX) AS BEGIN
            /* Strip to package name, version, and platform */
            SET @JsonPath = LEFT(
                RIGHT(
                    @JsonPath,
                    LEN(@JsonPath) - LEN(@PackagesDir) - 1
                ),
                (
                    LEN(@JsonPath) - LEN(@PackagesDir) - 1
                    - LEN(@PackageJsonFile) - 1
                )
            );

            /* Strip out platform, dialect and version */
            DECLARE @index INT = 0;
            WHILE @index < 3 BEGIN
                SET @JsonPath = REVERSE(
                    RIGHT(
                        REVERSE(@JsonPath),
                        LEN(@JsonPath)
                        - CHARINDEX(
                            ''/'',
                            REVERSE(@JsonPath)
                        )
                    )
                );

                SET @index += 1;
            END

            RETURN @JsonPath;
        END
        ';
    
    PRINT 'Created function Remote.PackageNameFromJsonPath';

    /* Create a procedure that can parse out a package name from a package.json path */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Remote.PackageVersionFromJsonPath (
            @JsonPath           NVARCHAR(MAX),
            @PackagesDir        NVARCHAR(800)   = ''packify-packages'',
            @PackageJsonFile    NVARCHAR(800)   = ''package.json''
        ) RETURNS NVARCHAR(MAX) AS BEGIN
            /* Strip to just package name and version */
            SET @JsonPath = LEFT(
                RIGHT(
                    @JsonPath,
                    LEN(@JsonPath) - LEN(@PackagesDir) - 1
                ),
                (
                    LEN(@JsonPath) - LEN(@PackagesDir) - 1
                    - LEN(@PackageJsonFile) - 1
                )
            );

            /* Strip the platform and dialect */
            DECLARE @index INT = 0;
            WHILE @index < 2 BEGIN
                SET @JsonPath = REVERSE(
                    RIGHT(
                        REVERSE(@JsonPath),
                        LEN(@JsonPath)
                        - CHARINDEX(
                            ''/'',
                            REVERSE(@JsonPath)
                        )
                    )
                );

                SET @index += 1;
            END

            SET @JsonPath = REVERSE(
                LEFT(
                    REVERSE(@JsonPath),
                    CHARINDEX(
                        ''/'',
                        REVERSE(@JsonPath)
                    ) - 1
                )
            );

            RETURN @JsonPath;
        END
        ';
    
    PRINT 'Created function Remote.PackageVersionFromJsonPath';

    /* Create a procedure to parse out the platform from the package json path */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Remote.PackagePlatformFromJsonPath (
            @JsonPath           NVARCHAR(MAX),
            @PackagesDir        NVARCHAR(800)   = ''packify-packages'',
            @PackageJsonFile    NVARCHAR(800)   = ''package.json''
        ) RETURNS NVARCHAR(MAX) AS BEGIN
            SET @JsonPath = LEFT(
                @JsonPath,
                LEN(@JsonPath) - LEN(@PackageJsonFile) - 1
            );

            SET @JsonPath = REVERSE(
                LEFT(
                    REVERSE(@JsonPath),
                    CHARINDEX(
                        ''/'',
                        REVERSE(@JsonPath)
                    ) - 1
                )
            );

            RETURN @JsonPath;
        END
        ';
    
    PRINT 'Created function Remote.PackagePlatformFromJsonPath';

    /* Create a procedure to parse out the dialect from the package json path */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Remote.PackageDialectFromJsonPath (
            @JsonPath           NVARCHAR(MAX),
            @PackagesDir        NVARCHAR(800)   = ''packify-packages'',
            @PackageJsonFile    NVARCHAR(800)   = ''package.json''
        ) RETURNS NVARCHAR(MAX) AS BEGIN
            SET @JsonPath = LEFT(
                @JsonPath,
                LEN(@JsonPath) - LEN(@PackageJsonFile) - 1
            );

            SET @JsonPath = REVERSE(
                RIGHT(
                    REVERSE(@JsonPath),
                    LEN(@JsonPath)
                    - CHARINDEX(
                        ''/'',
                        REVERSE(@JsonPath)
                    )
                )
            );

            SET @JsonPath = REVERSE(
                LEFT(
                    REVERSE(@JsonPath),
                    CHARINDEX(
                        ''/'',
                        REVERSE(@JsonPath)
                    ) - 1
                )
            );

            RETURN @JsonPath;
        END
        ';
    
    PRINT 'Created function Remote.PackageDialectFromJsonPath';

    /* Create a procedure that can update a repository's package cache given its id */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Remote.UpdateRepositoryCache
            @RepositoryID       INT
        WITH EXECUTE AS OWNER AS BEGIN
            SET XACT_ABORT ON;

            DECLARE
                @errorNumber        INT,
                @errorMessage       NVARCHAR(MAX);

            /* Check that the provided repository actually exists */
            IF NOT EXISTS (
                SELECT
                    *
                FROM
                    Remote.Repositories
                WHERE
                    [RepositoryID] = @RepositoryID
            ) BEGIN
                SET @errorNumber = Environment.GetErrorCode(''NoSuchRepositoryExists'');
                SET @errorMessage = CONCAT(
                    ''Repository with ID '', @RepositoryID, ''does not exist''
                );

                THROW
                    @errorNumber,
                    @errorMessage,
                    1;
            END

            /* Get required parameters for the repository */
            DECLARE
                @branch             NVARCHAR(800),
                @gitRepository      NVARCHAR(800),
                @listingURLFormat   NVARCHAR(800);
            SELECT
                @branch = [Branch],
                @gitRepository = [GitRepository],
                @listingURLFormat = [ListingURLFormat]
            FROM
                Remote.Repositories
            WHERE
                [RepositoryID] = @RepositoryID;

            /* Create the listing URL for this repo */
            DECLARE @listingURL NVARCHAR(MAX);
            DECLARE @parameters Utils.Parameters;
            INSERT INTO @parameters
            VALUES
                (''repo'', @gitRepository),
                (''branch'', @branch);

            EXEC Utils.ReplaceParameters
                @listingURLFormat,
                @parameters,
                @listingURL OUTPUT;
            
            /* Fetch the listing as json data */
            DECLARE @response NVARCHAR(MAX);
            EXEC Http.Get
                @listingURL,
                @Response = @response OUTPUT;
            
            BEGIN TRAN [TX_UpdatePackageCache];

                /* Extract all package.json files that are children of the packify-packages
                    subdirectory then parse out the package name */
                DECLARE @tblPackages TABLE (
                    [PackageName]       NVARCHAR(MAX),
                    [PackageVersion]    NVARCHAR(MAX),
                    [PackageDialect]    NVARCHAR(MAX),
                    [PackagePlatform]   NVARCHAR(MAX)
                );
                INSERT INTO
                    @tblPackages
                SELECT DISTINCT
                    PackageName = Remote.PackageNameFromJsonPath(
                        b.[value],
                        DEFAULT,
                        DEFAULT
                    ),
                    PackageVersion = Remote.PackageVersionFromJsonPath(
                        b.[value],
                        DEFAULT,
                        DEFAULT
                    ),
                    PackageDialect = Remote.PackageDialectFromJsonPath(
                        b.[value],
                        DEFAULT,
                        DEFAULT
                    ),
                    PackagePlatform = Remote.PackagePlatformFromJsonPath(
                        b.[value],
                        DEFAULT,
                        DEFAULT
                    )
                FROM
                    OPENJSON(@response, ''$.tree'') AS a
                CROSS APPLY
                    OPENJSON(a.[value]) AS b
                WHERE
                    b.[key] = ''path''
                    AND b.[value] LIKE ''packify-packages/%''
                    AND b.[value] LIKE ''%package.json'';
                
                /* Delete any old package cache for this repository */
                DELETE FROM
                    Remote.PackageCaches
                WHERE
                    [RepositoryID] = @repositoryID;
                
                /* Insert a new package cache record for this package cache */
                DECLARE @tblPackageCacheID TABLE (
                    [PackageCacheID]        INT
                );
                INSERT INTO Remote.PackageCaches (
                    [RepositoryID],
                    [CreateDateTime],
                    [ValidUntil]
                )
                OUTPUT
                    Inserted.PackageCacheID
                INTO 
                    @tblPackageCacheID
                VALUES (
                    @RepositoryID,
                    SYSDATETIMEOFFSET(),
                    DATEADD(
                        SECOND,
                        CAST(Environment.GetSetting(''DefaultCacheValidTime'') AS INT),
                        SYSDATETIMEOFFSET()
                    )
                );

                /* Get the ID of the package cache we just inserted */
                DECLARE @packageCacheID INT = (
                    SELECT
                        [PackageCacheID]
                    FROM
                        @tblPackageCacheID
                );

                /* Insert all of the packages we found */
                INSERT INTO Remote.RepositoryPackages (
                    [PackageCacheID],
                    [PackageName],
                    [VersionString],
                    [PackageDialect],
                    [PackagePlatform]
                )
                SELECT
                    @packageCacheID,
                    [PackageName],
                    [PackageVersion],
                    [PackageDialect],
                    [PackagePlatform]
                FROM
                    @tblPackages;
                
                /* Update version cache for all packages */
                DECLARE packageCursor CURSOR FOR
                SELECT
                    [RepositoryPackageID],
                    [VersionString]
                FROM
                    Remote.RepositoryPackages;
                
                DECLARE
                    @repositoryPackageID    INT,
                    @versionString          NVARCHAR(MAX);

                OPEN packageCursor;
                
                FETCH NEXT FROM
                    packageCursor
                INTO
                    @repositoryPackageID,
                    @versionString;
                
                WHILE @@FETCH_STATUS = 0 BEGIN
                    /* Parse the version string */
                    DECLARE @tblVersionParsed TABLE (
                        [SegmentOrdinal]    INT,
                        [SegmentValue]      NVARCHAR(MAX)
                    );
                    DELETE FROM @tblVersionParsed;

                    INSERT INTO
                        @tblVersionParsed
                    EXEC Packages.ParseVersion
                        @versionString;

                    /* Cache the parsed version */
                    INSERT INTO
                        Remote.RepositoryPackageVersions
                    SELECT
                        @repositoryPackageID,
                        *
                    FROM
                        @tblVersionParsed;

                    FETCH NEXT FROM
                        packageCursor
                    INTO
                        @repositoryPackageID,
                        @versionString;
                END

                CLOSE packageCursor;
                DEALLOCATE packageCursor;
            
            COMMIT;
        END
        ';
    
    PRINT 'Created procedure Remote.UpdateRepositoryCache';

    /* Create a procedure to update all out of date repository caches */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Remote.UpdateAllRepositoryCaches
            @ForceUpdates       BIT     = 0
        WITH EXECUTE AS OWNER AS BEGIN
            /* Cursor over all out-of-date package caches and update them */
            DECLARE repoCursor CURSOR FOR
            SELECT DISTINCT
                a.[RepositoryID],
                a.[Name]
            FROM
                Remote.Repositories AS a
            LEFT JOIN Remote.PackageCaches AS b ON
                a.[RepositoryID] = b.[RepositoryID]
                AND [ValidUntil] < SYSDATETIMEOFFSET()
            WHERE
                @ForceUpdates = 1
                OR b.[RepositoryID] IS NOT NULL;
            
            DECLARE
                @repositoryID   INT,
                @repositoryName NVARCHAR(MAX);
            
            OPEN repoCursor;

            FETCH NEXT FROM
                repoCursor
            INTO
                @repositoryID,
                @repositoryName;
            
            DECLARE @updateCount INT = 0;
            
            WHILE @@FETCH_STATUS = 0 BEGIN
                /* Update the current repository */
                EXEC Remote.UpdateRepositoryCache
                    @RepositoryID;
                
                PRINT CONCAT(
                    ''Updated cache for remote repository '''''',
                    @repositoryName,
                    ''''''''
                );

                SET @updateCount += 1;
                
                FETCH NEXT FROM
                    repoCursor
                INTO
                    @repositoryID,
                    @repositoryName;
            END

            CLOSE repoCursor;
            DEALLOCATE repoCursor;

            PRINT CONCAT(
                ''Updated '',
                @updateCount,
                '' repository cache'',
                IIF(
                    @updateCount = 1,
                    '''',
                    ''s''
                )
            );
        END
        ';
    
    PRINT 'Created procedure Remote.UpdateAllRepositoryCaches';

    /* Update all repository caches */
    EXEC Remote.UpdateAllRepositoryCaches
        @ForceUpdates = 1;
    
    PRINT 'Initialized package caches for all repositories';

REVERT
