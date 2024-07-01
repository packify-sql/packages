/*
 * 5-configure environment.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-26
 * Updated: 2024-06-28
 *
 * Configures the Packify environment and default settings
 *
 */

/* Run GRANT queries against master */
USE [master];

/* Grant permissions on the required OA procedures */
GRANT EXECUTE ON
    sp_OACreate
TO
    [PackifyUser];

GRANT EXECUTE ON
    sp_OADestroy
TO
    [PackifyUser];

GRANT EXECUTE ON
    sp_OAGetProperty
TO
    [PackifyUser];

GRANT EXECUTE ON
    sp_OAMethod
TO
    [PackifyUser];

PRINT 'Granted permissions on OLE Automation procedures to [PackifyUser]';


/* Operate against the database we created in the previous step */
USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'

    /* Create a schema for repository resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Environment];';
    
    PRINT 'Created [Environment] schema';

    /* Create a table to hold config settings */
    CREATE TABLE Environment.Settings (
        [SettingID]         INT PRIMARY KEY IDENTITY(1,1),
        [SettingName]       NVARCHAR(200) NOT NULL,
        [SettingValue]      SQL_VARIANT NOT NULL,
        [CreateDateTime]    DATETIMEOFFSET NOT NULL DEFAULT (SYSDATETIMEOFFSET()),
        [UpdateDateTime]    DATETIMEOFFSET NOT NULL DEFAULT (SYSDATETIMEOFFSET()),

        CONSTRAINT
            AK_Environment_Settings_SettingName
        UNIQUE (
            [SettingName]
        )
    );

    CREATE NONCLUSTERED INDEX
        IX_Environment_Settings_SettingName_SettingValue
    ON Environment.Settings (
        [SettingName]
    )
    INCLUDE (
        [SettingValue]
    );

    /* Create a trigger to update the UpdateDateTime column */
    EXEC sp_executesql
        N'
        CREATE TRIGGER Environment.TRG_Settings_UpdateDateTime ON Environment.Settings
        AFTER UPDATE AS BEGIN
            SET NOCOUNT ON;

            UPDATE
                Environment.Settings
            SET
                UpdateDateTime = SYSDATETIMEOFFSET()
            FROM
                Environment.Settings AS a
            INNER JOIN Inserted AS b ON
                a.[SettingID] = b.[SettingID];
        END
        ';

    /* Create function for getting settings */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Environment.GetSetting (
            @SettingName    NVARCHAR(200)
        ) RETURNS SQL_VARIANT AS BEGIN
            DECLARE @result SQL_VARIANT;

            SET @result = (
                SELECT
                    [SettingValue]
                FROM
                    Environment.Settings
                WHERE
                    [SettingName] = @SettingName
            );

            RETURN @result;
        END
        ';
    
    /* Create procedure for updating settings */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Environment.UpdateSetting
            @SettingName    NVARCHAR(200),
            @SettingValue   SQL_VARIANT
        WITH EXECUTE AS OWNER AS BEGIN
            SET NOCOUNT ON;

            /* Update if a setting already exists with this name */
            IF EXISTS (
                SELECT
                    *
                FROM
                    Environment.Settings
                WHERE
                    [SettingName] = @SettingName
            ) BEGIN
                UPDATE
                    Environment.Settings
                SET
                    [SettingValue] = @SettingValue
                WHERE
                    [SettingName] = @SettingName;
            END ELSE BEGIN
                /* Otherwise, just insert a new setting */
                INSERT INTO Environment.Settings (
                    [SettingName],
                    [SettingValue]
                )
                VALUES (
                    @SettingName,
                    @SettingValue
                );
            END
        END
        ';
    
    /* Register a setting for the default repository */
    DECLARE @defaultRepositoryID INT = (
        SELECT TOP 1
            [RepositoryID]
        FROM
            Remote.Repositories
        ORDER BY
            [RepositoryID] DESC
    );

    EXEC Environment.UpdateSetting
        @SettingName = 'DefaultRepository',
        @SettingValue = @defaultRepositoryID;

    /* Register settings for dialect and platform */
    EXEC Environment.UpdateSetting
        @SettingName = 'InstallDialect',
        @SettingValue = 'mssql';
    
    EXEC Environment.UpdateSetting
        @SettingName = 'InstallPlatform',
        @SettingValue = 'windows';
    
    EXEC Environment.UpdateSetting
        @SettingName = 'DefaultCacheValidTime',
        @SettingValue = 3600;
    
    DECLARE @settingsCount INT = (
        SELECT
            COUNT(*)
        FROM
            Environment.Settings
    );
    
    PRINT CONCAT(
        'Created Environment.Settings table and populated ',
        @settingsCount,
        ' setting',
        IIF(
            @settingsCount != 1,
            's',
            ''
        )
    );

    /* Create and populate tables for standard error codes */
    CREATE TABLE Environment.Errors (
        [ErrorID]           INT PRIMARY KEY IDENTITY(1,1),
        [ErrorCode]         INT NOT NULL,
        [ErrorName]         NVARCHAR(200) NOT NULL,
        [CreateDateTime]    DATETIMEOFFSET NOT NULL DEFAULT (SYSDATETIMEOFFSET()),

        CONSTRAINT
            AK_Environment_Errors_ErrorCode
        UNIQUE (
            [ErrorCode]
        ),

        CONSTRAINT
            AK_Environment_Errors_ErrorName
        UNIQUE (
            [ErrorName]
        )
    );

    CREATE TABLE Environment.ErrorCategories (
        [ErrorCategoryID]   INT PRIMARY KEY IDENTITY(1,1),
        [CategoryName]      NVARCHAR(200) NOT NULL,
        [StartCode]         INT NOT NULL,
        [EndCode]           INT NOT NULL,
        [CreateDateTime]    DATETIMEOFFSET NOT NULL DEFAULT (SYSDATETIMEOFFSET())
    );

    /* Insert parameter related errors */
    INSERT INTO Environment.Errors (
        [ErrorCode],
        [ErrorName]
    )
    VALUES
        (95000, 'ParameterCannotBeNull'),
        (95010, 'InvalidParameterValue');
    
    INSERT INTO Environment.ErrorCategories (
        [CategoryName],
        [StartCode],
        [EndCode]
    )
    VALUES (
        'ParameterErrors',
        95000,
        95000
    );

    /* Insert remote repository related errors */
    INSERT INTO Environment.Errors (
        [ErrorCode],
        [ErrorName]
    )
    VALUES
        (96000, 'NoSuchRepositoryExists');
    
    INSERT INTO Environment.ErrorCategories (
        [CategoryName],
        [StartCode],
        [EndCode]
    )
    VALUES (
        'RepositoryErrors',
        96000,
        96000
    );

    /* Create a function that will return an error code given its name */
    EXEC sp_executesql
        N'
        CREATE FUNCTION Environment.GetErrorCode (
            @ErrorName      NVARCHAR(200)
        ) RETURNS INT AS BEGIN
            DECLARE @errorCode INT = (
                SELECT TOP 1
                    [ErrorCode]
                FROM
                    Environment.Errors
                WHERE
                    [ErrorName] = @ErrorName
            );

            RETURN @errorCode;
        END
        ';

    /* Add http specific error codes */
    INSERT INTO Environment.Errors (
        [ErrorCode],
        [ErrorName]
    )
    VALUES
        (97000, 'HttpRequestCreateFailure'),
        (97010, 'HttpRequestOpenFailure'),
        (97020, 'HttpRequestHeaderSetFailure'),
        (97030, 'HttpRequestSendFailure'),
        (97040, 'HttpRequestGetStatusCodeFailure'),
        (97050, 'HttpRequestGetResponseFailure');

    /* Add all of the valid http status codes as error codes in the 97000 series */
    DECLARE @httpStatus INT = 100;
    WHILE @httpStatus < 600 BEGIN
        INSERT INTO Environment.Errors (
            [ErrorCode],
            [ErrorName]
        )
        VALUES (
            97000 + @httpStatus,
            CONCAT('HttpStatus', @httpStatus)
        );

        SET @httpStatus += 1;
    END

    INSERT INTO Environment.ErrorCategories (
        [CategoryName],
        [StartCode],
        [EndCode]
    )
    VALUES (
        'HttpStatusError',
        97100,
        97599
    );

    DECLARE
        @errorCodeCount INT = (
            SELECT
                COUNT(*)
            FROM
                Environment.Errors
        ),
        @errorCategoryCount INT = (
            SELECT
                COUNT(*)
            FROM
                Environment.ErrorCategories
        );
    
    PRINT 'Created Environment.Errors and Environment.ErrorCategories';
    PRINT CONCAT(
        'Registered ',
        @errorCodeCount,
        ' error codes and ',
        @errorCategoryCount,
        ' error categor',
        IIF(
            @errorCategoryCount = 1,
            'y',
            'ies'
        )
    );

REVERT
