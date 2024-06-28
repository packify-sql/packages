/*
 * 6-create-http-resources.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-27
 * Updated: 2024-06-27
 *
 * Sets up all resources required to issue HTTP requests
 *
 */

/* Operate against the database we created in the previous step */
USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'

    /* Create a schema for http resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Http];';
    
    PRINT 'Created [Http] schema';

    /* Create a procedure that will instantiate a new request object for us */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.CreateRequestObject AS BEGIN
            DECLARE
                @hresult        INT,
                @xmlHttpObject  INT,
                
                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);

            /* Instantiate a new request object */
            EXEC @hresult = sp_OACreate
                ''MSXML2.ServerXMLHTTP'',
                @xmlHttpObject OUTPUT;

            IF @hresult != 0 BEGIN
                SET @errorNumber = Environment.GetErrorCode(''HttpRequestCreateFailure'');
                SET @errorMessage = CONCAT(
                    ''Unable to create MSXML.ServerXMLHTTP object: Error '',
                    CONVERT(
                        NVARCHAR(MAX),
                        CAST(@hresult AS VARBINARY(8)),
                        1
                    )
                );

                THROW
                    @errorNumber,
                    @errorMessage,
                    1;
            END

            RETURN @xmlHttpObject;
        END
        ';

REVERT
