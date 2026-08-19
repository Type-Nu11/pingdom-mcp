local llmClient = require("src.ai.llmClient")

assert(type(llmClient) == "table", "llmClient should load")
assert(type(llmClient.createClient) == "function", "createClient should exist")
assert(type(llmClient.getProviderName) == "function", "getProviderName should exist")

print("AI adapter smoke OK")
