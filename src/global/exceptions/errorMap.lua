return {
    INVALID_INPUT = { status = 401, message = "Invalid username or password" },
    USER_ALREADY_EXISTS      = { status = 409, message = "User is already exists" },
    EMAIL_TAKEN        = { status = 409, message = "Email already exists" },
    INVALID_REFRESH     = { status = 401, message = "Invalid or expired refresh token" },
    FORBIDDEN          = { status = 403, message = "Forbidden" },
    NOT_FOUND      = { status = 404, message = "Not found" },
    INTERNAL_SERVER_ERROR     = { status = 500, message = "Internal server error" },
}