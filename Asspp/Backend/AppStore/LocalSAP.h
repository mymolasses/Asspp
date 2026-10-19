#ifndef ASSPP_LOCAL_SAP_H
#define ASSPP_LOCAL_SAP_H
char *AssppSAPSign(const char *input);
void AssppSAPCancel(const char *requestID);
void AssppSAPFree(char *value);
#endif
