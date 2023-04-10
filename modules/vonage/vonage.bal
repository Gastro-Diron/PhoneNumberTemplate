import ballerinax/vonage.sms as vs;
import ballerina/io;
vs:Client baseClient = check new;

configurable string api_key = io:readln("Input the vonage api_key: ");
configurable string api_secret = io:readln("Input the vonage api_secret: ");

public function vonageSMSOTP(string phoneNumber, string verificationCode) returns error? {
    vs:NewMessage message = {
        api_key: api_key,
        'from: "VERIFY",
        to: phoneNumber,
        api_secret: api_secret,
        text: "Please enter this code to verify your Phone Number. "+
    "Your code is "+verificationCode+". This verification code will expire in 5 minutes."
    };
    vs:InlineResponse200|error response = baseClient->sendAnSms(message);
}