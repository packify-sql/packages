/*
 * 8-package-versioning.sql
 *
 * Authors: Will Hinson
 * Created: 2024-07-01
 * Updated: 2024-07-01
 *
 * Creates resources related to package versioning
 *
 */

/* Operate against the database we created in the previous step */
USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'
    /* Create a schema for package-related resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Packages];';
    
    PRINT 'Created [Packages] schema';

    /* Create a procedure to parse a package version string */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Packages.ParseVersion
            @VersionString      NVARCHAR(800)
        AS BEGIN
            DECLARE
                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);
            
            /* These are the allowed characters for a version string as well as
                the valid segment separators */
            DECLARE
                @allowedCharacters  NVARCHAR(MAX) = ''abcdefghijklmnopqrstuvwxyz0123456789'',
                @separators         NVARCHAR(MAX) = ''._-+'';

            /* If no version string was provided, return an empty table */
            IF @VersionString IS NULL BEGIN
                SET @errorNumber = Environment.GetErrorCode(''ParameterCannotBeNull'');
                SET @errorMessage = ''Parameter @VersionString cannot be NULL'';

                GOTO Error;
            END

            /* Otherwise, loop over all of the allowed values and track all segments */
            DECLARE @tblSegments TABLE (
                [SegmentOrdinal]    INT,
                [SegmentValue]      NVARCHAR(MAX)
            );
            DECLARE
                @currentSegment     NVARCHAR(MAX) = '''',
                @segmentPosition    INT = 1,
                @offset             INT = 1;
            
            WHILE @offset <= LEN(@VersionString) BEGIN
                DECLARE @currentChar NCHAR(1) = SUBSTRING(
                    @VersionString,
                    @offset,
                    1
                );

                /* Check if this character is a separator character */
                IF CHARINDEX(@currentChar, @separators) != 0 BEGIN
                    /* Ensure there was actually a segment preceding it */
                    IF @currentSegment = '''' BEGIN
                        SET @errorNumber = Environment.GetErrorCode(''InvalidParameterValue'');
                        SET @errorMessage = CONCAT(
                            ''Invalid version string syntax at offset '',
                            @offset
                        );

                        GOTO Error;
                    END

                    /* Insert the previous segment and set up for the next one */
                    INSERT INTO
                        @tblSegments
                    VALUES (
                        @segmentPosition,
                        @currentSegment
                    );

                    SET @segmentPosition += 1;
                    SET @currentSegment = '''';
                END ELSE BEGIN
                    /* Ensure that this character is considered valid */
                    IF CHARINDEX(@currentChar, @allowedCharacters) = 0 BEGIN
                        SET @errorNumber = Environment.GetErrorCode(''InvalidParameterValue'');
                        SET @errorMessage = CONCAT(
                            ''Invalid character in version string: '''''',
                            @currentChar,
                            ''''''''
                        );

                        GOTO Error;
                    END

                    SET @currentSegment += @currentChar;
                END

                SET @offset += 1;
            END

            /* Insert a final segment if there was one */
            IF LEN(@currentSegment) != 0 BEGIN
                INSERT INTO
                    @tblSegments
                VALUES (
                    @segmentPosition,
                    @currentSegment
                );
            END

            /* Return all of the segments that we got */
            SELECT
                *
            FROM
                @tblSegments;
            
            RETURN;
        
        Error:
            THROW
                @errorNumber,
                @errorMessage,
                1;
        END
        ';
    
    PRINT 'Created procedure Packages.ParseVersion';

REVERT