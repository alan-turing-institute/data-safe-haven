@{
    Severity="Error"
    ExcludeRules=@(
        # Ignore error when using 'ConvertTo-SecureString' with '-AsPlainText'
        # and a string argument rather than an encrypted string
        "PSAvoidUsingConvertToSecureStringWithPlainText",
        # Ignore error when a function has both 'Username' and 'Password'
        # arguments
        "PSAvoidUsingUsernameAndPasswordParams"
        )
}
