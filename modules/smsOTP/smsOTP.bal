import wso2/choreo.sendsms;

sendsms:Client sendSmsClient = check new ();

public function sendSMSOTP (string toNumber, string verificationCode) returns error? {
    string message = "Please enter this code in the application UI to verify your Phone Number:"+
    "Your code is "+verificationCode+". This verification code will expire in 5 minutes.";
    string response = check sendSmsClient -> sendSms(toNumber, message);
}
