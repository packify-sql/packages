/*
 * 6-create-http-resources.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-27
 * Updated: 2024-06-28
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

    /* Create a custom table type to contain request headers */
    CREATE TYPE Http.RequestHeaders AS TABLE (
        [HeaderName]        NVARCHAR(400) PRIMARY KEY,
        [HeaderValue]       NVARCHAR(4000) NOT NULL
    );

    CREATE TABLE Http.DefaultHeaders (
        [DefaultHeaderID]   INT PRIMARY KEY IDENTITY(1,1),
        [HeaderName]        NVARCHAR(400) NOT NULL,
        [HeaderValue]       NVARCHAR(4000) NOT NULL,

        CONSTRAINT
            AK_Http_DefaultHeaders_HeaderName
        UNIQUE (
            [HeaderName]
        )
    );

    INSERT INTO Http.DefaultHeaders (
        [HeaderName],
        [HeaderValue]
    )
    VALUES
        ('User-Agent', 'packify/0.2.0'),
        ('Cache-Control', 'no-cache'),
        ('Pragma', 'no-cache');

    PRINT 'Created type Http.RequestHeaders and table Http.DefaultHeaders';

    /* Create a procedure that will instantiate a new request object for us */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.CreateRequestObject
        WITH EXECUTE AS OWNER AS BEGIN
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
    
    PRINT 'Created procedure Http.CreateRequestObject';

    /* Create a procedure that will open a provided request for us */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.OpenRequestObject
            @RequestHandle      INT,
            @Method             NVARCHAR(200),
            @TargetUrl          NVARCHAR(4000)
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @hresult        INT,

                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);

            /* Open the HTTP request with the provided method */
            EXEC @hresult = sp_OAMethod
                @RequestHandle,
                ''open'',
                NULL,
                @Method,
                @TargetUrl,
                false;
            
            IF @hresult != 0 BEGIN
                SET @errorNumber = Environment.GetErrorCode(''HttpRequestOpenFailure'');
                SET @errorMessage = CONCAT(
                    ''Unable to open request: Error '',
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
        END
        ';
    
    PRINT 'Created procedure Http.OpenRequestObject';
    
    /* Create a procedure that will set headers in a given request object */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.SetRequestHeaders
            @RequestHandle  INT,
            @Headers        Http.RequestHeaders     READONLY
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @hresult        INT,

                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);

            /* Merge the user-provided headers and the default headers */
            SELECT
                *
            INTO
                #tblHeaders
            FROM
                @Headers;
            
            MERGE INTO
                #tblHeaders AS Target
            USING
                Http.DefaultHeaders AS Source
            ON
                Target.[HeaderName] = Source.[HeaderName]
            WHEN NOT MATCHED BY TARGET THEN
                INSERT (
                    [HeaderName],
                    [HeaderValue]
                )
                VALUES (
                    Source.[HeaderName],
                    Source.[HeaderValue]
                );
            
            /* Cursor over all of the headers and set them */
            DECLARE headersCursor CURSOR FOR
            SELECT
                [HeaderName],
                [HeaderValue]
            FROM
                #tblHeaders;
            
            DECLARE
                @headerName     NVARCHAR(400),
                @headerValue    NVARCHAR(4000);
            
            OPEN headersCursor;

            FETCH NEXT FROM
                headersCursor
            INTO
                @headerName,
                @headerValue;
            
            WHILE @@FETCH_STATUS = 0 BEGIN
                /* Set the current request header */
                EXEC @hresult = sp_OAMethod
                    @RequestHandle,
                    ''setRequestHeader'',
                    NULL,
                    @headerName,
                    @headerValue;
                
                IF @hresult != 0 BEGIN
                    SET @errorNumber = Environment.GetErrorCode(''HttpRequestHeaderSetFailure'');
                    SET @errorMessage = CONCAT(
                        ''Unable to set '', @headerName, '' header for request: Error '',
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

                /* Fetch the next header key and value */
                FETCH NEXT FROM
                    headersCursor
                INTO
                    @headerName,
                    @headerValue;
            END
        END
        ';
    
    PRINT 'Created procedure Http.SetRequestHeaders';
    
    /* Create a procedure that will instantiate a request and open it/set headers */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.CreateRequest
            @Method     NVARCHAR(200),
            @TargetUrl  NVARCHAR(4000),
            @Headers    Http.RequestHeaders     READONLY
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @requestHandle      INT,
                @hresult            INT,
                
                @errorNumber        INT,
                @errorMessage       NVARCHAR(MAX);
            
            BEGIN TRY
                /* Create and open a request object instance */
                EXEC @requestHandle = Http.CreateRequestObject;

                EXEC Http.OpenRequestObject
                    @requestHandle,
                    @Method,
                    @TargetUrl;

                /* Set all headers on the request object */
                EXEC Http.SetRequestHeaders
                    @requestHandle,
                    @Headers;

                RETURN @requestHandle;
            END TRY
            BEGIN CATCH
                /* Ensure the request handle is closed on error */
                IF @requestHandle IS NOT NULL BEGIN
                    EXEC sp_OADestroy
                        @requestHandle;
                END;

                THROW;
            END CATCH
        END
        ';

    PRINT 'Created procedure Http.CreateRequest';

    /* Create a procedure that will send an HTTP request */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.SendRequest
            @RequestHandle      INT,
            @Body               NVARCHAR(MAX)
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @hresult        INT,
                
                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);
            
            IF @Body IS NULL BEGIN
                SET @body = '''';
            END

            EXEC @hresult = sp_OAMethod
                @RequestHandle,
                ''send'',
                NULL,
                @Body;

            IF @hresult != 0 BEGIN
                SET @errorNumber = Environment.GetErrorCode(''HttpRequestSendFailure'');
                SET @errorMessage = CONCAT(
                    ''Unable to send request: Error '',
                    CONVERT(
                        NVARCHAR(MAX),
                        CAST(@hresult AS VARBINARY(8)),
                        1
                    ),
                    IIF(
                        @hresult = 0x80072EE7,
                        CONCAT(
                            '' (It is likely your database server cannot '',
                            ''connect to the remote server. Check your '',
                            ''database server''''s Internet connection.)''
                        ),
                        ''''
                    )
                );

                THROW
                    @errorNumber,
                    @errorMessage,
                    1;
            END
        END
        ';
    
    PRINT 'Created procedure Http.SendRequest';
    
    /* Create a procedure that will get the response status code and content */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.GetResponse
            @RequestHandle      INT,
            @Response           NVARCHAR(MAX)       OUTPUT
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @hresult        INT,
                @statusCode     INT,

                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);

            /* Get the status code and check for success */
            EXEC @hresult = sp_OAGetProperty
                @RequestHandle,
                ''status'',
                @statusCode OUT;

            IF @hresult != 0 BEGIN
                SET @errorNumber = Environment.GetErrorCode(''HttpRequestGetStatusCodeFailure'');
                SET @errorMessage = CONCAT(
                    ''Unable to get response status code: Error '',
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

            /* Get the content of the response */
            DECLARE @tblResult TABLE (
                [ResultField]   NVARCHAR(MAX)
            );
            INSERT INTO
                @tblResult
            EXEC @hresult = sp_OAGetProperty
                @RequestHandle,
                ''responseText'';

            IF @hresult != 0 BEGIN
                SET @errorNumber = Environment.GetErrorCode(''HttpRequestGetResponseFailure'');
                SET @errorMessage = CONCAT(
                    ''Unable to get response: Error '',
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

            SELECT TOP 1
                @Response = [ResultField]
            FROM
                @tblResult;

            RETURN @statusCode;
        END
        ';
    
    PRINT 'Created procedure Http.GetResponse';

    /* Create a procedure to send an HTTP request of an arbitrary method to a
        provided remote URL */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.PerformRequest
            @Method             NVARCHAR(200),
            @TargetUrl          NVARCHAR(4000),
            @Body               NVARCHAR(MAX)           = NULL,
            @Headers            Http.RequestHeaders     READONLY,
            @Response           NVARCHAR(MAX)           OUTPUT
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @requestHandle      INT,
                @statusCode         INT;

            /* Instantiate the request object */
            EXEC @requestHandle = Http.CreateRequest
                @Method,
                @TargetUrl,
                @Headers;
            
            BEGIN TRY
                /* Send the request */
                EXEC Http.SendRequest
                    @requestHandle,
                    @Body;
                
                /* Get the response and status code */
                EXEC @statusCode = Http.GetResponse
                    @requestHandle,
                    @Response OUTPUT;
            END TRY
            BEGIN CATCH
                /* Ensure the request handle is closed on error */
                IF @requestHandle IS NOT NULL BEGIN
                    EXEC sp_OADestroy
                        @requestHandle;
                END;

                THROW;
            END CATCH
            
            /* Delete the request object that we created */
            EXEC sp_OADestroy
                @requestHandle;
            
            RETURN @statusCode;
        END
        ';
    
    PRINT 'Created procedure Http.PerformRequest';

    /* Create a procedure to throw an error if the status code is non-200 */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.ThrowOnErrorStatus
            @StatusCode     INT
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @errorNumber        INT,
                @errorMessage       NVARCHAR(MAX);

            IF @StatusCode NOT BETWEEN 200 AND 299 BEGIN
                SET @errorNumber = 97000 + @StatusCode;
                SET @errorMessage = CONCAT(
                    ''Server responded with error status code '',
                    @statusCode
                );

                THROW
                    @errorNumber,
                    @errorMessage,
                    1;
            END
        END
        ';
    
    PRINT 'Created procedure Http.ThrowOnErrorStatus';

    /* Create procedures to perform http GET and POST */
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.Get
            @TargetUrl          NVARCHAR(4000),
            @Body               NVARCHAR(MAX)           = NULL,
            @Headers            Http.RequestHeaders     READONLY,
            @Response           NVARCHAR(MAX)           OUTPUT
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @statusCode     INT,

                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);
            
            /* Perform the actual request */
            EXEC @statusCode = Http.PerformRequest
                ''GET'',
                @TargetUrl,
                @Body,
                @Headers,
                @Response OUTPUT;
            
            EXEC Http.ThrowOnErrorStatus
                @statusCode;
            
            RETURN @statusCode;
        END
        ';
    
    EXEC sp_executesql
        N'
        CREATE PROCEDURE Http.Post
            @TargetUrl          NVARCHAR(4000),
            @Body               NVARCHAR(MAX)           = NULL,
            @Headers            Http.RequestHeaders     READONLY,
            @Response           NVARCHAR(MAX)           OUTPUT
        WITH EXECUTE AS OWNER AS BEGIN
            DECLARE
                @statusCode     INT,

                @errorNumber    INT,
                @errorMessage   NVARCHAR(MAX);
            
            /* Perform the actual request */
            EXEC @statusCode = Http.PerformRequest
                ''POST'',
                @TargetUrl,
                @Body,
                @Headers,
                @Response OUTPUT;
            
            EXEC Http.ThrowOnErrorStatus
                @statusCode;
            
            RETURN @statusCode;
        END
        ';
    
    PRINT 'Created procedures Http.Get and Http.Post';

REVERT
