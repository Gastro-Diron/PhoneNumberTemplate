import ballerina/http;
import flow1.codegen;
import flow1.formatData;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerina/sql;
import flow1.smsOTP;
// import flow1.vonage;
import ballerina/time;
import ballerina/io;


configurable string orgname = io:readln("Input your organization name: ");
configurable string clientID = io:readln("Input the ClientID of the Asgardeo application: ");
configurable string clientSecret = io:readln("Input the ClientSecret of the Asgardeo application: ");
configurable string dbHost = io:readln("Input the host of your Database: ");
configurable string dbUser = io:readln("Input the user of your Database: ");
configurable string dbPassword = io:readln("Input the password of your Database: ");
configurable string dbName = io:readln("Input the name of your Database: ");
configurable string dbPortStr = io:readln("Input the port your Database :");


int dbPort = check int:fromString(dbPortStr);

string createScope = "internal_user_mgt_create";
string listScope = "internal_user_mgt_list";

http:Client Register = check new ("https://api.asgardeo.io/t/"+orgname+"/scim2", httpVersion = http:HTTP_1_1);

mysql:Client dbClient = check new (dbHost, dbUser, dbPassword, dbName, dbPort);

service on new http:Listener (9000){
    
    resource function post users (@http:Payload UserEntry userEntry) returns string|error|ConflictingEmailsError {
        string toNumber = userEntry.phoneNumber;
        FullUser|error gotUser = getUser(userEntry.email);

        if gotUser is FullUser{
            return {
                body: {
                    errmsg: string:'join(" ", "Conflicting emails:"+userEntry.email)
                }
            }; 

        }else {
            json token = check makeRequest(orgname, clientID, clientSecret, listScope);
    
            json Msg = formatData:checkDuplicate(userEntry.email);
            json token_type_any = check token.token_type;
            json access_token_any = check token.access_token;
            string token_type = token_type_any.toString();  
            string access_token = access_token_any.toString();
            http:Response postData = check Register->post(path = "/Users/.search", message = Msg, headers = {"Authorization": token_type+" "+access_token, "Content-Type": "application/scim+json"});
            json num = check postData.getJsonPayload();
            int result = check num.totalResults;
            if result == 0 {
                string verificationCode = check codegen:genCode();
                error? sms = smsOTP:sendSMSOTP(toNumber,verificationCode);
                // error? sms = vonage:vonageSMSOTP(toNumber.substring(1,12),verificationCode);
                time:Utc verificationSentTime = time:utcNow();
                error? data = createUser(userEntry.email, userEntry.name, userEntry.phoneNumber, verificationCode, "DEFAULT PASSWORD", verificationSentTime[0], 0);
                return "User has been added to the Temporary UserStore";
            } else {
                return "Already a user exists with the same email";
            }
        }
    }

    resource function get users/[string email] () returns string|error {
        FullUser|error gotUser = getUser(email);

        if gotUser is FullUser{
            string verificationCode = check codegen:genCode();
            error? sms  = smsOTP:sendSMSOTP(gotUser.phoneNumber,verificationCode);
            // error? sms = vonage:vonageSMSOTP(gotUser.phoneNumber.substring(1,12),verificationCode);
            error? userDeletion = deleteUser(gotUser.email);
            time:Utc verificationSentTime = time:utcNow();
            error? data = createUser(gotUser.email, gotUser.name, gotUser.phoneNumber, verificationCode, "DEFAULT PASSWORD", verificationSentTime[0], 0); 
            return "New verification Code has been sent to your mobile number.";
        } else {
            return "The email does not exist";
        }
    }

    resource function post users/[string email] (string password) returns string|InvalidEmailError|error{
        FullUser|error gotUser = getUser(email);
            if gotUser is FullUser {
                error? userUpdation = updateUser(email, password);

                json Msg = formatData:formatdata(gotUser.name,gotUser.email,password);
                json token = check makeRequest(orgname,clientID,clientSecret,createScope);
                json token_type_any = check token.token_type;
                json access_token_any = check token.access_token;
                string token_type = token_type_any.toString();  
                string access_token = access_token_any.toString();
                http:Response|http:ClientError postData = check Register->post(path = "/Users", message = Msg, headers = {"Authorization": token_type+" "+access_token, "Content-Type": "application/scim+json"});
                if postData is http:Response {
                    int num = postData.statusCode;
                    if num == 201 {
                            error? userDeletion = deleteUser(email);
                    }
                    return "The code is correct. The statusCode is "+num.toString();
                } else {
                    return "The code is correct but error in creating the user";
                }
                
            } else {
                return {
                    body: {
                        errmsg: string `Invalid Email: ${email}`
                    }
                };
            }
    }

    resource function delete users/[string email] () returns string|InvalidEmailError {
        FullUser|error gotUser = getUser(email);

        if gotUser is FullUser {
            error? userDeletion = deleteUser(email);
            return "User has been deleted successfully";
        } else {
            return {
                body: {
                    errmsg: string `Invalid Email: ${email}`
                }
            };
        }
    }
    
    resource function post verify (@http:Payload VerifyEntry verifyEntry) returns string|response {
        FullUser|error gotUser = getUser(verifyEntry.email);
        
        if gotUser is FullUser {
            time:Utc verificationReceivedTime = time:utcNow();
            error? receivedTimeUpdation = updateReceivedTime(gotUser.email, verificationReceivedTime[0]);
            
            string verificationCode = gotUser.code;
            int verificationSentTime = gotUser.sentTime;

            int timeDifference = verificationReceivedTime[0] - verificationSentTime;
            response result;

            if timeDifference < 300 {
                if verifyEntry.code == verificationCode {
                    result = {status: "valid"};
                } else {
                    result = {status: "invalid"};
                }
                return result;
            } else {
                return "The verification Code has expired";
            }
        } else{
            return "The Email does not exist";
        }
    }
}

public type UserEntry record {|
    readonly string email;
    string name;
    string phoneNumber;
|};

public type FullUser record {|
    *UserEntry;
    string code;
    string password;
    int sentTime;
    int receivedTime;
|};

public type ConflictingEmailsError record {|
    *http:Conflict;
    ErrorMsg body;
|};

public type ErrorMsg record {|
    string errmsg;
|};

public type InvalidEmailError record {|
    *http:NotFound;
    ErrorMsg body;
|};

public type VerifyEntry record {|
    readonly string email;
    string code;
|};

public type response record {|
    readonly string status;
|};

function createUser(string email, string name, string phoneNumber, string code, string password, int sentTime, int receivedTime) returns error?{
    sql:ParameterizedQuery query = `INSERT INTO User_Details(email, name, phoneNumber, code, password, sentTime, receivedTime)
                                  VALUES (${email}, ${name}, ${phoneNumber}, ${code}, ${password}, ${sentTime}, ${receivedTime})`;
    sql:ExecutionResult result = check dbClient->execute(query);
}

function getUser(string email) returns FullUser|error{
    sql:ParameterizedQuery query = `SELECT * FROM User_Details
                                    WHERE email = ${email}`;
    FullUser resultRow = check dbClient->queryRow(query);
    return resultRow;
}

function deleteUser(string email) returns error?{
    sql:ParameterizedQuery query = `DELETE from User_Details WHERE email = ${email}`;
    sql:ExecutionResult result = check dbClient->execute(query);
}

function updateUser(string email, string password) returns error?{
    sql:ParameterizedQuery query = `UPDATE User_Details SET password = ${password} WHERE email = ${email}`;
    sql:ExecutionResult result = check dbClient->execute(query);
}

function updateReceivedTime(string email, int receivedTime) returns error?{
    sql:ParameterizedQuery query = `UPDATE User_Details SET receivedTime = ${receivedTime} WHERE email = ${email}`;
    sql:ExecutionResult result = check dbClient->execute(query);
}

public function makeRequest(string orgName, string clientId, string clientSecret, string scope) returns json|error|error {
    http:Client clientEP = check new ("https://api.asgardeo.io",
        auth = {
            username: clientId,
            password: clientSecret
        },
         httpVersion = http:HTTP_1_1
    );
    http:Request req = new;
    req.setPayload("grant_type=client_credentials&scope="+scope, "application/x-www-form-urlencoded");
    http:Response response = check clientEP->/t/[orgName]/oauth2/token.post(req);
    json tokenInfo = check response.getJsonPayload();
    return tokenInfo;
}