-- src/global/exceptions/errorMap.lua
return {
    INVALID_INPUT         = { status = 400, message = "Invalid input" },
    INVALID_CREDENTIALS   = { status = 401, message = "Invalid username or password" },
    USER_ALREADY_EXISTS   = { status = 409, message = "User already exists" },
    EMAIL_TAKEN           = { status = 409, message = "Email already exists" },
    INVALID_REFRESH       = { status = 401, message = "Invalid or expired refresh token" },
    FORBIDDEN             = { status = 403, message = "Forbidden" },
    NOT_FOUND             = { status = 404, message = "Not found" },
    INTERNAL_SERVER_ERROR = { status = 500, message = "Internal server error" },

    -- recommendation / llm (gemini)
    LLM_NO_KEY         = { status = 500, message = "LLM API key not configured" },
    LLM_CONNECT_FAILED = { status = 502, message = "Failed to reach LLM provider" },
    LLM_BAD_JSON       = { status = 502, message = "Invalid LLM response" },
    LLM_ERROR          = { status = 502, message = "LLM returned an error" },
    LLM_EMPTY          = { status = 502, message = "Empty LLM response" },
    LLM_NO_TOOLCALL    = { status = 502, message = "LLM did not call the tool" },
    LLM_BAD_ARGS       = { status = 502, message = "LLM tool arguments invalid" },
    GEOCODE_FAILED     = { status = 422, message = "Failed to geocode region (Korean addresses only)" },
    NO_DATA_IN_REGION  = { status = 404, message = "No population data within the requested area" },
}