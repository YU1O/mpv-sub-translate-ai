/*
    Real-time subtitle translation for PotPlayer using OpenAI ChatGPT API
*/

// Plugin Information Functions
string GetTitle() {
    return "{$CP949=ChatGPT 번역$}"
         + "{$CP950=ChatGPT 翻譯$}"
         + "{$CP936=ChatGPT 翻译$}"
         + "{$CP0=ChatGPT Translate$}";
}

// The version number will be replaced during the installation process
string GetVersion() {
    return "1.9.2";
}

string GetDesc() {
    return "Real-time subtitle translation using OpenAI ChatGPT.";
}

string GetLoginTitle() {
    return "{$CP949=OpenAI 모델 및 API 키 구성$}"
         + "{$CP950=OpenAI 模型與 API 金鑰配置$}"
         + "{$CP936=OpenAI 模型与 API 密钥配置$}"
         + "{$CP0=OpenAI Model + API URL and API Key Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=모델 이름, API 주소, 선택적 nullkey, 지연(ms) 및 재시도 모드(0-3)를 입력하십시오 (예: gpt-5-nano|https://api.openai.com/v1/chat/completions|nullkey|500|retry1).$}"
         + "{$CP949=\n\n설치 프로그램에서 미리 구성한 값이 있다면 PotPlayer 패널에서 다시 설정하기 전까지 해당 값을 사용하며, 패널에서 설정하면 해당 설정이 항상 우선 적용됩니다.$}"
         + "{$CP949=\n\n선택적으로 cache=auto 또는 cache=off 를 추가하여 문맥 캐시 모드를 제어할 수 있으며, auto 는 지원되지 않을 경우 chat 방식으로 자동 전환됩니다.$}"
         + "{$CP950=請輸入模型名稱、API 地址、可選的 nullkey、延遲毫秒與重試模式(0-3)（例如: gpt-5-nano|https://api.openai.com/v1/chat/completions|nullkey|500|retry1）。$}"
         + "{$CP950=\n\n如果安裝包已寫入預設配置，在 PotPlayer 面板中未重新設定之前會沿用這些配置；一旦在面板中調整，將始終以面板設定為準。$}"
         + "{$CP950=\n\n可選加上 cache=auto 或 cache=off 以控制上下文快取模式，auto 會在不支援時自動回退至 chat。$}"
         + "{$CP936=请输入模型名称（可留空：留空则请求不带 model 字段，由服务端选用当前已加载的模型，如 LM Studio/Ollama）、API 地址、API 密钥（本地服务可留空或填 nullkey）、可选的延迟毫秒和重试模式(0-3)（例如: deepseek-chat|https://api.deepseek.com/v1/chat/completions|sk-xxx）。$}"
         + "{$CP936=\n\n如果安装包已经写入默认配置，在 PotPlayer 面板中没有重新设置之前会继续使用这些配置；一旦在面板中修改，将始终以面板设置为准。$}"
         + "{$CP936=\n\n可选追加 cache=auto 或 cache=off 用于控制上下文缓存模式，auto 在不支持时会自动回退到 chat。$}"
         + "{$CP0=Please enter the model name (leave empty to let the server use its currently loaded model), the API URL, the API key (leave empty or 'nullkey' for local servers), optional delay in ms, and retry mode 0-3 (e.g., deepseek-chat|https://api.deepseek.com/v1/chat/completions|sk-xxx).$}"
         + "{$CP0=\n\nInstaller defaults will remain in effect until you update the settings in PotPlayer's panel, and any panel changes will always take priority.$}"
         + "{$CP0=\n\nOptionally append cache=auto or cache=off to control context caching. Auto falls back to chat when caching is unsupported.$}"
         + "{$CP0=\n\nFor OpenAI official API you can also append retention=24h (or cache24h) to extend prompt cache retention. For Gemini official API you can append gcache=cachedContents/... to reuse an explicit cache.$}";
}

string GetUserText() {
    return "{$CP949=모델 이름|API 주소|nullkey|지연(ms)|재시도 모드|캐시 모드 (현재: " + GPT_selected_model + " | " + GPT_apiUrl + " | " + GPT_delay_ms + " | " + GPT_retry_mode + " | " + GPT_context_cache_mode + ")$}"
         + "{$CP950=模型名稱|API 地址|nullkey|延遲ms|重試模式|快取模式 (目前: " + GPT_selected_model + " | " + GPT_apiUrl + " | " + GPT_delay_ms + " | " + GPT_retry_mode + " | " + GPT_context_cache_mode + ")$}"
         + "{$CP936=模型名称|API 地址|nullkey|延迟ms|重试模式|缓存模式 (目前: " + GPT_selected_model + " | " + GPT_apiUrl + " | " + GPT_delay_ms + " | " + GPT_retry_mode + " | " + GPT_context_cache_mode + ")$}"
         + "{$CP0=Model Name|API URL|nullkey|Delay ms|Retry mode|Cache mode|Retention|Gemini cached_content (Current: " + GPT_selected_model + " | " + GPT_apiUrl + " | " + GPT_delay_ms + " | " + GPT_retry_mode + " | " + GPT_context_cache_mode + " | " + GPT_prompt_cache_retention + " | " + GPT_gemini_cached_content + ")$}";
}

string GetPasswordText() {
    return "{$CP949=API 키:$}"
         + "{$CP950=API 金鑰:$}"
         + "{$CP936=API 密钥:$}"
         + "{$CP0=API Key:$}";
}

// Global Variables
// Pre-configured values (auto-filled by installer)
// 预置默认值：不预设任何服务商，全部留空。首次使用在 PotPlayer「账户信息」面板配置一次，
// 配置会持久化，之后每次选中插件都直接生效。字段规则：
//   模型留空 = 请求不带 model 字段，由服务端选用当前已加载的模型（LM Studio/Ollama 等）
//   密钥留空或 nullkey = 不发送 Authorization 头（本地服务无需鉴权）
string GPT_pre_api_key = ""; // will be replaced during installation
string GPT_pre_selected_model = ""; // will be replaced during installation
string GPT_pre_apiUrl = ""; // will be replaced during installation
string GPT_pre_delay_ms = "0"; // will be replaced during installation
string GPT_pre_retry_mode = "0"; // will be replaced during installation
string GPT_pre_context_token_budget = "2000"; // approx. tokens reserved for context (0 = auto)
// 上下文预算按 8k 级本地模型的保守值取默认；官方大上下文 API 可在面板调大
string GPT_pre_context_cache_mode = "off"; // auto | off
string GPT_pre_prompt_cache_retention = ""; // ""(default), in-memory, 24h (OpenAI official only)
string GPT_pre_gemini_cached_content = ""; // optional cachedContents/... name for Gemini OpenAI-compatible endpoint
string GPT_pre_small_model = "0"; // 0 | 1
string GPT_pre_check_hallucination = "0"; // 0 | 1
string GPT_pre_model_token_limits_json = "{}"; // serialized token limit rules (injected by installer)
string GPT_pre_api_temperature = "0.3"; // 采样温度；翻译不需要创造性，低温更稳更快；留空则用服务端默认

// Context-specific identifiers to prevent collisions with other subtitle translator scripts.
const string GPT_CTX_TRANSLATION_FAILURE_WARNING_PREFIX = "[Translation failed - please share a screenshot with the developer] ";
const int GPT_MAX_RETRY_ATTEMPTS = 10;

string GPT_api_key = GPT_pre_api_key;
string GPT_selected_model = GPT_pre_selected_model; // Default model
string GPT_apiUrl = GPT_pre_apiUrl; // Default API URL
string GPT_delay_ms = GPT_pre_delay_ms; // Request delay in ms
string GPT_retry_mode = GPT_pre_retry_mode; // Auto retry mode
string GPT_context_token_budget = GPT_pre_context_token_budget; // Approximate token budget for context
string GPT_context_cache_mode = GPT_pre_context_cache_mode; // auto | off
string GPT_prompt_cache_retention = GPT_pre_prompt_cache_retention; // "" | in-memory | 24h
string GPT_gemini_cached_content = GPT_pre_gemini_cached_content; // cachedContents/... (optional)
string GPT_small_model = GPT_pre_small_model;
string GPT_check_hallucination = GPT_pre_check_hallucination;
string GPT_api_temperature = GPT_pre_api_temperature;
string GPT_UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
// 目标语言的成人字幕语域锚点词表（顿号分隔）。标记之间留空 = 仅用泛化选词规则。
// 作用域锁定：只对源文本身露骨的句子生效，医疗/非性语境保持正常术语。
// 词面不写死在代码里，由用户从 explicit_vocab_hint.txt 注入（替换两个标记之间的内容）。
string GPT_explicit_vocab_hint = "小穴、肉棒、口交、做爱、后庭、淫水、潮吹、内射、高潮、骚、奶子、奶头、舔、插入、抽插、骑乘、后入、发情、淫叫、勃起";
array<string> GPT_subtitleHistory;  // Global subtitle history (源文)
array<string> GPT_translationHistory; // 与 subtitleHistory 一一对应的译文历史（上下文以 user/assistant 消息对注入）
string GPT_lastDstLang = ""; // 目标语言变化时清空历史，避免跨语言上下文干扰
bool GPT_context_cache_disabled_for_session = false;
string GPT_context_cache_disable_key = "";
bool GPT_token_rules_initialized = false;
int GPT_default_model_token_limit = 4096;
array<string> GPT_token_rule_types;
array<string> GPT_token_rule_values;
array<int> GPT_token_rule_limits;

// Helper functions to load configuration while respecting installer defaults
string BuildConfigSentinel(const string &in key) {
    return "#__POTPLAYER_CFG_UNSET__#" + key + "#__";
}

string LoadInstallerConfig(const string &in key, const string &in installerValue, const string &in fallbackKey = "") {
    string sentinel = BuildConfigSentinel(key);
    string storedValue = HostLoadString(key, sentinel);
    if (storedValue == sentinel && fallbackKey != "") {
        string fallbackSentinel = BuildConfigSentinel(fallbackKey);
        string fallbackValue = HostLoadString(fallbackKey, fallbackSentinel);
        if (fallbackValue != fallbackSentinel && fallbackValue != "")
            return fallbackValue;
    }
    if (storedValue == sentinel || (storedValue == "" && installerValue != ""))
        return installerValue;
    return storedValue;
}

void EnsureConfigDefault(const string &in key, const string &in value) {
    string sentinel = BuildConfigSentinel(key);
    string stored = HostLoadString(key, sentinel);
    if (stored == sentinel || (stored == "" && value != ""))
        HostSaveString(key, value);
}

void EnsureInstallerDefaultsPersisted() {
    EnsureConfigDefault("gpt_api_key", GPT_pre_api_key);
    EnsureConfigDefault("gpt_selected_model", GPT_pre_selected_model);
    EnsureConfigDefault("gpt_apiUrl", GPT_pre_apiUrl);
    EnsureConfigDefault("gpt_delay_ms", GPT_pre_delay_ms);
    EnsureConfigDefault("gpt_retry_mode", GPT_pre_retry_mode);
    EnsureConfigDefault("gpt_context_token_budget", GPT_pre_context_token_budget);
    EnsureConfigDefault("gpt_context_cache_mode", GPT_pre_context_cache_mode);
    EnsureConfigDefault("gpt_prompt_cache_retention", GPT_pre_prompt_cache_retention);
    EnsureConfigDefault("gpt_gemini_cached_content", GPT_pre_gemini_cached_content);
    EnsureConfigDefault("gpt_small_model", GPT_pre_small_model);
    EnsureConfigDefault("gpt_check_hallucination", GPT_pre_check_hallucination);
    EnsureConfigDefault("gpt_api_temperature", GPT_pre_api_temperature);
}

void RefreshConfiguration() {
    EnsureInstallerDefaultsPersisted();
    GPT_api_key = LoadInstallerConfig("gpt_api_key", GPT_pre_api_key, "wc_api_key");
    GPT_selected_model = LoadInstallerConfig("gpt_selected_model", GPT_pre_selected_model, "wc_selected_model");
    GPT_apiUrl = LoadInstallerConfig("gpt_apiUrl", GPT_pre_apiUrl, "wc_apiUrl");
    GPT_delay_ms = LoadInstallerConfig("gpt_delay_ms", GPT_pre_delay_ms, "wc_delay_ms");
    GPT_retry_mode = LoadInstallerConfig("gpt_retry_mode", GPT_pre_retry_mode, "wc_retry_mode");
    GPT_context_token_budget = LoadInstallerConfig("gpt_context_token_budget", GPT_pre_context_token_budget);
    GPT_context_cache_mode = NormalizeCacheMode(LoadInstallerConfig("gpt_context_cache_mode", GPT_pre_context_cache_mode));
    GPT_prompt_cache_retention = NormalizePromptCacheRetention(LoadInstallerConfig("gpt_prompt_cache_retention", GPT_pre_prompt_cache_retention));
    GPT_gemini_cached_content = LoadInstallerConfig("gpt_gemini_cached_content", GPT_pre_gemini_cached_content).Trim();
    GPT_small_model = LoadInstallerConfig("gpt_small_model", GPT_pre_small_model);
    GPT_check_hallucination = LoadInstallerConfig("gpt_check_hallucination", GPT_pre_check_hallucination);
    GPT_api_temperature = LoadInstallerConfig("gpt_api_temperature", GPT_pre_api_temperature);
}

// Supported Language List
array<string> LangTable =
{
    "", // Auto Detect
    "af", // Afrikaans
    "sq", // Albanian
    "am", // Amharic
    "ar", // Arabic
    "hy", // Armenian
    "az", // Azerbaijani
    "eu", // Basque
    "be", // Belarusian
    "bn", // Bengali
    "bs", // Bosnian
    "bg", // Bulgarian
    "ca", // Catalan
    "ceb", // Cebuano
    "ny", // Chichewa
    "zh-CN", // Chinese (Simplified)
    "zh-TW", // Chinese (Traditional)
    "co", // Corsican
    "hr", // Croatian
    "cs", // Czech
    "da", // Danish
    "nl", // Dutch
    "en", // English
    "eo", // Esperanto
    "et", // Estonian
    "tl", // Filipino
    "fi", // Finnish
    "fr", // French
    "fy", // Frisian
    "gl", // Galician
    "ka", // Georgian
    "de", // German
    "el", // Greek
    "gu", // Gujarati
    "ht", // Haitian Creole
    "ha", // Hausa
    "haw", // Hawaiian
    "he", // Hebrew
    "hi", // Hindi
    "hmn", // Hmong
    "hu", // Hungarian
    "is", // Icelandic
    "ig", // Igbo
    "id", // Indonesian
    "ga", // Irish
    "it", // Italian
    "ja", // Japanese
    "jw", // Javanese
    "kn", // Kannada
    "kk", // Kazakh
    "km", // Khmer
    "ko", // Korean
    "ku", // Kurdish (Kurmanji)
    "ky", // Kyrgyz
    "lo", // Lao
    "la", // Latin
    "lv", // Latvian
    "lt", // Lithuanian
    "lb", // Luxembourgish
    "mk", // Macedonian
    "ms", // Malay
    "mg", // Malagasy
    "ml", // Malayalam
    "mt", // Maltese
    "mi", // Maori
    "mr", // Marathi
    "mn", // Mongolian
    "my", // Myanmar (Burmese)
    "ne", // Nepali
    "no", // Norwegian
    "ps", // Pashto
    "fa", // Persian
    "pl", // Polish
    "pt", // Portuguese
    "pa", // Punjabi
    "ro", // Romanian
    "ru", // Russian
    "sm", // Samoan
    "gd", // Scots Gaelic
    "sr", // Serbian
    "st", // Sesotho
    "sn", // Shona
    "sd", // Sindhi
    "si", // Sinhala
    "sk", // Slovak
    "sl", // Slovenian
    "so", // Somali
    "es", // Spanish
    "su", // Sundanese
    "sw", // Swahili
    "sv", // Swedish
    "tg", // Tajik
    "ta", // Tamil
    "te", // Telugu
    "th", // Thai
    "tr", // Turkish
    "uk", // Ukrainian
    "ur", // Urdu
    "uz", // Uzbek
    "vi", // Vietnamese
    "cy", // Welsh
    "xh", // Xhosa
    "yi", // Yiddish
    "yo", // Yoruba
    "zu"  // Zulu
};

array<string> GetSrcLangs() {
    array<string> ret = LangTable;
    return ret;
}

array<string> GetDstLangs() {
    array<string> ret = LangTable;
    return ret;
}

bool IsDigits(const string &in s) {
    if (s.length() == 0)
        return false;
    for (uint i = 0; i < s.length(); i++) {
        uint8 c = s[i];
        if (c < 48 || c > 57)
            return false;
    }
    return true;
}

int ParseInt(const string &in s) {
    int v = 0;
    for (uint i = 0; i < s.length(); i++) {
        uint8 c = s[i];
        if (c < 48 || c > 57)
            return 0;
        v = v * 10 + (c - 48);
    }
    return v;
}

int GetRetryLoopLimit(int retryModeInt) {
    int maxRetries = retryModeInt;
    if (maxRetries < 0)
        maxRetries = 0;
    if (retryModeInt == 2 || retryModeInt == 3)
        maxRetries = GPT_MAX_RETRY_ATTEMPTS - 1;
    if (maxRetries > GPT_MAX_RETRY_ATTEMPTS - 1)
        maxRetries = GPT_MAX_RETRY_ATTEMPTS - 1;
    return maxRetries;
}

string BuildAuthHeaders(const string &in key) {
    string trimmedKey = key.Trim();
    string lowerKey = string(trimmedKey).MakeLower();
    string headers = "Content-Type: application/json";
    if (trimmedKey != "" && lowerKey != "nullkey")
        headers = "Authorization: Bearer " + trimmedKey + "\n" + headers;
    return headers;
}

// ServerLogin 各成功分支的共同收尾：写入全局配置并持久化
string PersistLoginSuccess(const string &in userModel, const string &in storedApiKey,
                           const string &in apiUrlLocal, const string &in normalizedCacheMode,
                           const string &in retentionToken, const string &in geminiCacheToken,
                           const string &in successMsg) {
    GPT_selected_model = userModel;
    GPT_api_key = storedApiKey;
    HostSaveString("gpt_api_key", GPT_api_key);
    HostSaveString("gpt_selected_model", GPT_selected_model);
    HostSaveString("gpt_apiUrl", apiUrlLocal);
    HostSaveString("gpt_delay_ms", GPT_delay_ms);
    HostSaveString("gpt_retry_mode", GPT_retry_mode);
    GPT_context_cache_mode = normalizedCacheMode;
    HostSaveString("gpt_context_cache_mode", GPT_context_cache_mode);
    GPT_prompt_cache_retention = retentionToken;
    HostSaveString("gpt_prompt_cache_retention", GPT_prompt_cache_retention);
    GPT_gemini_cached_content = geminiCacheToken;
    HostSaveString("gpt_gemini_cached_content", GPT_gemini_cached_content);
    HostSaveString("gpt_small_model", GPT_small_model);
    HostSaveString("gpt_check_hallucination", GPT_check_hallucination);
    HostSaveString("gpt_api_temperature", GPT_api_temperature);
    GPT_context_cache_disabled_for_session = false;
    GPT_context_cache_disable_key = "";
    return successMsg;
}

// API Key and API Base verification process
string ServerLogin(string User, string Pass) {
    RefreshConfiguration();
    string errorAccum = "";
    User = User.Trim();
    Pass = Pass.Trim();
    string lowerPass = string(Pass).MakeLower();
    array<string> tokens;
    int start = 0;
    for (int i = 0; i <= int(User.length()); i++) {
        if (i == int(User.length()) || User.substr(i, 1) == "|") {
            string token = User.substr(start, i - start).Trim();
            tokens.insertLast(token);
            start = i + 1;
        }
    }
    string userModel = "";
    string customApiUrl = "";
    bool allowNullApiKey = (Pass == "" || lowerPass == "nullkey");
    string delayToken = "";
    string retryToken = "";
    string cacheToken = "";
    string promptCacheRetentionToken = GPT_prompt_cache_retention;
    string geminiCachedContentToken = GPT_gemini_cached_content;
    string smallModelToken = "";
    string halluToken = "";
    string normalizedCacheMode = GPT_context_cache_mode;
    if (tokens.length() >= 1) {
        userModel = tokens[0];
    }
    for (int i = 1; i < int(tokens.length()); i++) {
        string t = tokens[i];
        string lowered = ToLower(t);
        if (lowered == "nullkey")
            allowNullApiKey = true;
        else if (lowered.length() >= 5 && lowered.substr(0,5) == "retry" && IsDigits(t.substr(5)))
            retryToken = t.substr(5);
        else if (IsDigits(t))
            delayToken = t;
        else if (lowered.length() >= 6 && lowered.substr(0,6) == "cache=")
            cacheToken = lowered.substr(6);
        else if (lowered == "cacheauto" || lowered == "cacheon" || lowered == "cache")
            cacheToken = "auto";
        else if (lowered == "cacheoff" || lowered == "nocache")
            cacheToken = "off";
        else if (lowered.length() >= 10 && lowered.substr(0,10) == "retention=")
            promptCacheRetentionToken = lowered.substr(10);
        else if (lowered == "cache24h")
            promptCacheRetentionToken = "24h";
        else if (lowered == "cachemem" || lowered == "cachememory")
            promptCacheRetentionToken = "in-memory";
        else if (lowered.length() >= 15 && lowered.substr(0,15) == "cachedcontent=")
            geminiCachedContentToken = t.substr(15).Trim();
        else if (lowered.length() >= 15 && lowered.substr(0,15) == "cached_content=")
            geminiCachedContentToken = t.substr(15).Trim();
        else if (lowered.length() >= 7 && lowered.substr(0,7) == "gcache=")
            geminiCachedContentToken = t.substr(7).Trim();
        else if (lowered == "gcacheoff" || lowered == "nocachedcontent")
            geminiCachedContentToken = "";
        else if (lowered == "smallmodel=1" || lowered == "smallmodel")
            smallModelToken = "1";
        else if (lowered == "smallmodel=0")
            smallModelToken = "0";
        else if (lowered == "checkhallucination=1" || lowered == "hallucination=1")
            halluToken = "1";
        else if (lowered == "checkhallucination=0" || lowered == "hallucination=0")
            halluToken = "0";
        else if (customApiUrl == "")
            customApiUrl = t;
    }
    if (retryToken != "")
        GPT_retry_mode = retryToken;
    if (delayToken != "")
        GPT_delay_ms = delayToken;
    if (cacheToken != "")
        normalizedCacheMode = NormalizeCacheMode(cacheToken);
    else
        normalizedCacheMode = NormalizeCacheMode(normalizedCacheMode);
    promptCacheRetentionToken = NormalizePromptCacheRetention(promptCacheRetentionToken);
    if (smallModelToken != "")
        GPT_small_model = smallModelToken;
    if (halluToken != "")
        GPT_check_hallucination = halluToken;
    
    if (userModel == "")
        userModel = GPT_selected_model;

    // 模型允许留空：请求体不带 model 字段，由服务端（如 LM Studio）选用当前加载的模型
    string apiUrlLocal = "";
    if (customApiUrl != "") {
        apiUrlLocal = customApiUrl;
        while (apiUrlLocal != "" && apiUrlLocal.substr(apiUrlLocal.length()-1, 1) == "/")
            apiUrlLocal = apiUrlLocal.substr(0, apiUrlLocal.length()-1);
    } else {
        apiUrlLocal = GPT_apiUrl;
    }
    if (apiUrlLocal.Trim() == "") {
        errorAccum += "API URL not entered. Please enter a valid API URL.\n";
        return errorAccum;
    }

    if (Pass == "")
        Pass = GPT_api_key;
    
    if (string(Pass).MakeLower() == "nullkey")
        allowNullApiKey = true;

    if (!allowNullApiKey && Pass == "") {
        errorAccum += "API Key not configured. Please enter a valid API Key.\n";
        return errorAccum;
    }
    string storedApiKey = (lowerPass == "nullkey" || (allowNullApiKey && Pass == "")) ? "nullkey" : Pass;
    bool isOfficial = IsOpenAIOfficialApiUrl(apiUrlLocal);
    bool isGemini = IsGeminiApiUrl(apiUrlLocal);
    string verifyHeaders = BuildAuthHeaders(Pass);
    string testSystemMsg = "You are a test assistant.";
    string testUserMsg = "Hello";
    string testPromptCacheKey = BuildPromptCacheKey(userModel, "verify", "verify");
    string testRequestData = BuildChatPayload(
        userModel,
        testSystemMsg,
        testUserMsg,
        isOfficial,
        testPromptCacheKey,
        promptCacheRetentionToken,
        isGemini,
        geminiCachedContentToken,
        "" // 连接测试无需历史上下文
    );
    string testResponse = HostUrlGetString(apiUrlLocal, GPT_UserAgent, verifyHeaders, testRequestData);
    if (testResponse != "") {
        JsonReader testReader;
        JsonValue testRoot;
            if (testReader.parse(testResponse, testRoot)) {
                if (testRoot.isObject() && testRoot["choices"].isArray() && testRoot["choices"].size() > 0) {
                    return PersistLoginSuccess(userModel, storedApiKey, apiUrlLocal, normalizedCacheMode,
                        promptCacheRetentionToken, geminiCachedContentToken, "200 ok");
                } else {
                    if (testRoot.isObject() && testRoot["error"].isObject() && testRoot["error"]["message"].isString())
                        errorAccum += "Test message error: " + testRoot["error"]["message"].asString() + "\n";
                    else
                    errorAccum += "Test message response invalid.\n";
            }
        } else {
            errorAccum += "Failed to parse test message response.\n";
        }
    } else {
        errorAccum += "No response from server when sending test message.\n";
    }
    if (apiUrlLocal.find("chat/completions") == -1) {
        string correctedApiUrl = apiUrlLocal + "/chat/completions";
        bool correctedIsOfficial = IsOpenAIOfficialApiUrl(correctedApiUrl);
        bool correctedIsGemini = IsGeminiApiUrl(correctedApiUrl);
        string correctedTestRequestData = BuildChatPayload(
            userModel,
            testSystemMsg,
            testUserMsg,
            correctedIsOfficial,
            testPromptCacheKey,
            promptCacheRetentionToken,
            correctedIsGemini,
            geminiCachedContentToken,
            ""
        );
        string correctedTestResponse = HostUrlGetString(correctedApiUrl, GPT_UserAgent, verifyHeaders, correctedTestRequestData);
        if (correctedTestResponse != "") {
            JsonReader correctedReader;
            JsonValue correctedRoot;
            if (correctedReader.parse(correctedTestResponse, correctedRoot)) {
                if (correctedRoot.isObject() && correctedRoot["choices"].isArray() && correctedRoot["choices"].size() > 0) {
                    apiUrlLocal = correctedApiUrl;
                    return PersistLoginSuccess(userModel, storedApiKey, apiUrlLocal, normalizedCacheMode,
                        promptCacheRetentionToken, geminiCachedContentToken,
                        "Warning: Your API base was auto-corrected to: " + apiUrlLocal + "\n200 ok");
                } else {
                    if (correctedRoot.isObject() && correctedRoot["error"].isObject() && correctedRoot["error"]["message"].isString())
                        errorAccum += "Auto-correction test error: " + correctedRoot["error"]["message"].asString() + "\n";
                    else
                        errorAccum += "Auto-correction test response invalid.\n";
                }
            } else {
                errorAccum += "Failed to parse auto-correction test response.\n";
            }
        } else {
            errorAccum += "No response from server after auto-correction.\n";
        }
    }
    if (isOfficial) {
        string verifyUrl = "";
        int pos = apiUrlLocal.find("chat/completions");
        if (pos != -1)
            verifyUrl = apiUrlLocal.substr(0, pos) + "models";
        else
            verifyUrl = "https://api.openai.com/v1/models";
        string verifyResponse = HostUrlGetString(verifyUrl, GPT_UserAgent, verifyHeaders, "");
        if (verifyResponse == "")
            errorAccum += "Server connection failed: Unable to retrieve model list. Check network and API Base.\n";
        else {
            JsonReader reader;
            JsonValue root;
            if (!reader.parse(verifyResponse, root))
                errorAccum += "Failed to parse model list response. Check API Base and API Key.\n";
            else {
                if (root.isObject() && root["error"].isObject() && root["error"]["message"].isString())
                    errorAccum += "API error during model list retrieval: " + root["error"]["message"].asString() + "\n";
                else if (root.isObject() && root["data"].isArray()) {
                    bool modelFound = false;
                    int dataSize = root["data"].size();
                    for (int i = 0; i < dataSize; i++) {
                        JsonValue element = root["data"][i];
                        if (element.isObject() && element["id"].isString()) {
                            if (element["id"].asString() == userModel) {
                                modelFound = true;
                                break;
                            }
                        }
                    }
                    if (!modelFound)
                        errorAccum += "The specified model '" + userModel + "' is not available in the official API.\n";
                } else
                    errorAccum += "Invalid format of model list response.\n";
            }
        }
    } else {
        errorAccum += "API verification via model list skipped for third-party API Base.\n";
    }
    if (!allowNullApiKey && Pass.length() < 20)
        errorAccum += "API Key verification failed: API Key length may too short. Please verify your API Key.\n";
    if (errorAccum != "")
        return "API verification failed with the following issues:\n\n" + errorAccum;
    return "Unknown error during API verification. Please check your network, API Key, and API Base settings.\n";
}

// Logout Interface to clear model name and API Key
void ServerLogout() {
    GPT_api_key = "";
    GPT_selected_model = GPT_pre_selected_model;
    GPT_apiUrl = GPT_pre_apiUrl;
    GPT_delay_ms = GPT_pre_delay_ms;
    GPT_retry_mode = GPT_pre_retry_mode;
    GPT_context_token_budget = GPT_pre_context_token_budget;
    GPT_context_cache_mode = GPT_pre_context_cache_mode;
    GPT_prompt_cache_retention = GPT_pre_prompt_cache_retention;
    GPT_gemini_cached_content = GPT_pre_gemini_cached_content;
    GPT_small_model = GPT_pre_small_model;
    GPT_api_temperature = GPT_pre_api_temperature;
    GPT_context_cache_disabled_for_session = false;
    GPT_context_cache_disable_key = "";
    HostSaveString("gpt_api_key", "");
    HostSaveString("gpt_selected_model", GPT_selected_model);
    HostSaveString("gpt_apiUrl", GPT_apiUrl);
    HostSaveString("gpt_delay_ms", GPT_delay_ms);
    HostSaveString("gpt_retry_mode", GPT_retry_mode);
    HostSaveString("gpt_context_token_budget", GPT_context_token_budget);
    HostSaveString("gpt_context_cache_mode", GPT_context_cache_mode);
    HostSaveString("gpt_prompt_cache_retention", GPT_prompt_cache_retention);
    HostSaveString("gpt_gemini_cached_content", GPT_gemini_cached_content);
    HostSaveString("gpt_small_model", GPT_small_model);
    HostSaveString("gpt_check_hallucination", GPT_check_hallucination);
    HostSaveString("gpt_api_temperature", GPT_api_temperature);
    HostPrintUTF8("Successfully logged out.\n");
}

// 剥离译文尾部多余标点：模型几乎每行都补句号，偶见以逗号/冒号/分号收尾（通常是
// 它把两行源字幕合并了）。保留 ... … ！ ？ ~ —— 等带语气的收尾。
// 全角标点是 3 字节 UTF-8，必须整串 substr 比较，不能逐字节判断。
string TrimTrailingPunctuation(const string &in s) {
    string t = s.Trim();
    while (int(t.length()) > 0) {
        int len = int(t.length());
        if (len >= 3) {
            string tail3 = t.substr(len - 3, 3);
            if (tail3 == "...") break; // 省略号有语气，保留
            if (tail3 == "。" || tail3 == "，" || tail3 == "、" || tail3 == "；"
                || tail3 == "：" || tail3 == "．" || tail3 == "｡") {
                t = t.substr(0, len - 3);
                continue;
            }
        }
        string tail1 = t.substr(len - 1, 1);
        if (tail1 == "." || tail1 == "," || tail1 == ";" || tail1 == ":") {
            t = t.substr(0, len - 1);
            continue;
        }
        break;
    }
    return t;
}

// JSON String Escape Function
string JsonEscape(const string &in input) {
    string output = input;
    output.replace("\\", "\\\\");
    output.replace("\"", "\\\"");
    output.replace("\n", "\\n");
    output.replace("\r", "\\r");
    output.replace("\t", "\\t");
    output.replace("/", "\\/");
    return output;
}

// Function to estimate token count based on character length
int EstimateTokenCount(const string &in text) {
    return int(float(text.length()) / 4);
}

// Function to get the model's maximum context length
int GetModelMaxTokens(const string &in modelName) {
    EnsureTokenRulesLoaded();
    string trimmedModel = modelName.Trim();
    if (trimmedModel == "")
        return GPT_default_model_token_limit;

    for (uint i = 0; i < GPT_token_rule_types.length(); i++) {
        string matchType = GPT_token_rule_types[i];
        string matchValue = GPT_token_rule_values[i];
        int limit = GPT_token_rule_limits[i];
        if (matchType == "prefix") {
            if (trimmedModel.length() >= matchValue.length() &&
                trimmedModel.substr(0, matchValue.length()) == matchValue)
                return limit;
        } else if (matchType == "contains") {
            if (trimmedModel.find(matchValue) != -1)
                return limit;
        } else if (matchType == "equals") {
            if (trimmedModel == matchValue)
                return limit;
        }
    }

    return GPT_default_model_token_limit;
}

bool StartsWithText(const string &in s, const string &in p) {
    return s.length() >= p.length() && s.substr(0, p.length()) == p;
}

// 清理模型输出中常见的包装：整体包裹引号、"Here is the translation:"/"以下是翻译："类前导语。
// 小参数模型即使被禁止也常犯这些毛病，展示前剥掉
string CleanTranslationOutput(const string &in s) {
    string t = s.Trim();
    if (int(t.length()) >= 2) {
        string head1 = t.substr(0, 1);
        string tail1 = t.substr(int(t.length()) - 1, 1);
        string head3 = int(t.length()) >= 3 ? t.substr(0, 3) : "";
        string tail3 = int(t.length()) >= 3 ? t.substr(int(t.length()) - 3, 3) : "";
        bool wrapped = (head1 == "\"" && tail1 == "\"") || (head1 == "'" && tail1 == "'")
            || (head3 == "\u201C" && tail3 == "\u201D")   // “ ”
            || (head3 == "\u300C" && tail3 == "\u300D")   // 「 」
            || (head3 == "\u300E" && tail3 == "\u300F");  // 『 』
        if (wrapped) {
            int cut = (head1 == "\"" || head1 == "'") ? 1 : 3; // CJK 引号是 3 字节
            t = t.substr(cut, int(t.length()) - cut * 2).Trim();
        }
    }
    array<string> prefixes = {
        "Here is the translation:", "Here's the translation:",
        "Here is the translated text:", "Here is the translated subtitle:",
        "Here is your translation:", "Translation:", "translation:",
        "翻译：", "翻译:", "译文：", "译文:", "以下是翻译：", "以下是翻译:", "以下是译文：", "以下是译文:"
    };
    bool changed = true;
    while (changed) {
        changed = false;
        for (uint i = 0; i < prefixes.length(); i++) {
            if (StartsWithText(t, prefixes[i])) {
                t = t.substr(prefixes[i].length()).Trim();
                changed = true;
            }
        }
    }
    return t;
}

// ---- 与 mpv 脚本一致的源文预处理 ----

// 剥掉 ASS {...} 与 HTML <...> 标签：它们不参与翻译，留着反而会让模型模仿输出标签
string StripSubtitleTags(const string &in s) {
    string t = HostRegExpRemove(s, "\\{[^}]*\\}");
    t = HostRegExpRemove(t, "<[^<>]*>");
    return t.Trim();
}

// 无可译内容的行：剥标签/音符/省略号/空白/数字/ASCII 标点后为空。
// 直接原样返回，省掉一次注定无意义的 API 请求（♪♪、---、123 之类）
bool IsNoopLine(const string &in s) {
    string t = StripSubtitleTags(s);
    t.replace("♪", ""); t.replace("♫", ""); t.replace("♬", ""); t.replace("♩", "");
    t.replace("…", ""); t.replace("—", ""); t.replace("–", ""); t.replace("·", "");
    t.replace("...", "");
    for (uint i = 0; i < t.length(); i++) {
        uint8 c = t[i];
        if (c >= 0x80)
            return false; // 任何非 ASCII 字节都视为有真实文字
        // ASCII: 字母 → 有内容；其余（空白/标点/数字）继续看
        if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122))
            return false;
    }
    return true;
}

// 重复行缓存：影视字幕里同一句台词（歌曲副歌、口头禅）反复出现，
// 命中就直接复用译文，不发请求。源文先行剥标签，带标签/不带标签共享缓存
array<string> GPT_translationCacheKeys;
array<string> GPT_translationCacheVals;
int GPT_translationCacheLimit = 1024;

int FindTranslationCache(const string &in key) {
    // 从最新往回找：重复台词往往时间上邻近
    for (int i = int(GPT_translationCacheKeys.length()) - 1; i >= 0; i--) {
        if (GPT_translationCacheKeys[i] == key)
            return i;
    }
    return -1;
}

void StoreTranslationCache(const string &in key, const string &in value) {
    if (int(GPT_translationCacheKeys.length()) >= GPT_translationCacheLimit) {
        GPT_translationCacheKeys.resize(0);
        GPT_translationCacheVals.resize(0);
    }
    GPT_translationCacheKeys.insertLast(key);
    GPT_translationCacheVals.insertLast(value);
}

// Translation Function
string Translate(string Text, string &in SrcLang, string &in DstLang) {
    RefreshConfiguration();

    // API 密钥允许留空：BuildAuthHeaders 对空密钥/nullkey 均不发送 Authorization 头，
    // 本地服务（LM Studio/Ollama 等）无需鉴权，不再因空密钥直接放弃翻译
    if (GPT_apiUrl.Trim() == "") {
        HostPrintUTF8("API URL not configured. Please set it in the account settings menu.\n");
        return FormatFailureTranslation("", "API URL is required. Configure model/URL/key in the account settings menu.");
    }

    if (DstLang == "" || DstLang == "Auto Detect") {
        HostPrintUTF8("Target language not specified. Please select a target language.\n");
        return "";
    }

    if (SrcLang == "" || SrcLang == "Auto Detect") {
        SrcLang = "";
    }

    // 源文预处理：剥标签（模型不模仿标签，带/不带标签共享缓存）→ 无可译内容直接跳过 → 重复行走缓存
    Text = StripSubtitleTags(Text);
    if (Text == "" || IsNoopLine(Text)) {
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string cacheKey = DstLang + "|" + Text;
    int cacheIdx = FindTranslationCache(cacheKey);
    if (cacheIdx != -1) {
        GPT_subtitleHistory.insertLast(Text);
        GPT_translationHistory.insertLast(GPT_translationCacheVals[cacheIdx]);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return GPT_translationCacheVals[cacheIdx];
    }

    // 源文在翻译成功后才与译文一起入历史，保证两个数组始终对齐
    // （否则某行翻译失败时，下一行的上下文会出现有源文没译文的错位）

    int maxTokens = GetModelMaxTokens(GPT_selected_model);
    int safeBudget = maxTokens - 1000;
    if (safeBudget < 0)
        safeBudget = maxTokens;
    if (safeBudget < 0)
        safeBudget = 0;

    int configuredBudget = ParseInt(GPT_context_token_budget);
    if (configuredBudget <= 0 || configuredBudget > safeBudget)
        configuredBudget = safeBudget;

    // 目标语言变化时清空历史：混入其他语言的上下文会误导模型
    if (GPT_lastDstLang != DstLang) {
        GPT_subtitleHistory.resize(0);
        GPT_translationHistory.resize(0);
        GPT_lastDstLang = DstLang;
    }

    int currentTokens = EstimateTokenCount(Text);
    if (currentTokens < 0)
        currentTokens = 0;
    int availableForContext = safeBudget - currentTokens;
    if (availableForContext < 0)
        availableForContext = 0;
    if (availableForContext > configuredBudget)
        availableForContext = configuredBudget;

    // 上下文按“前文→前译”成对收集（源文数组与译文数组严格对齐），整对放不下就截断收集
    array<int> contextIdx;
    int usedContextTokens = 0;
    int idx = int(GPT_subtitleHistory.length()) - 1;
    while (idx >= 0 && usedContextTokens < availableForContext) {
        string subtitle = GPT_subtitleHistory[idx];
        int subtitleTokens = EstimateTokenCount(subtitle);
        if (subtitleTokens <= 0 || idx >= int(GPT_translationHistory.length())) {
            idx--;
            continue;
        }
        // 译文通常比源文长，预算必须把译文也算进去，否则长历史下
        // 实际注入的上下文总量会超出模型上下文窗口
        int pairTokens = subtitleTokens + EstimateTokenCount(GPT_translationHistory[idx]);
        if (usedContextTokens + pairTokens <= availableForContext) {
            contextIdx.insertAt(0, idx);
            usedContextTokens += pairTokens;
        } else {
            break;
        }
        idx--;
    }

    string contextMessages = "";
    for (uint ctxIndex = 0; ctxIndex < contextIdx.length(); ctxIndex++) {
        int histIdx = contextIdx[ctxIndex];
        contextMessages += "{\"role\":\"user\",\"content\":\"" + JsonEscape(GPT_subtitleHistory[histIdx]) + "\"},";
        contextMessages += "{\"role\":\"assistant\",\"content\":\"" + JsonEscape(GPT_translationHistory[histIdx]) + "\"},";
    }

    int historyBudget = configuredBudget;
    if (historyBudget <= 0)
        historyBudget = safeBudget;
    if (historyBudget < 0)
        historyBudget = 0;
    int historyTarget = historyBudget > 0 ? int(historyBudget / 16) : 0;
    if (historyTarget < 96)
        historyTarget = 96;
    if (historyTarget > 2048)
        historyTarget = 2048;
    int shrinkTarget = historyTarget - 64;
    if (shrinkTarget < 64)
        shrinkTarget = historyTarget / 2;
    if (shrinkTarget < 32)
        shrinkTarget = 32;
    const uint historyTargetCount = historyTarget > 0 ? uint(historyTarget) : 0;
    const uint shrinkTargetCount = shrinkTarget > 0 ? uint(shrinkTarget) : 0;
    if (GPT_subtitleHistory.length() > historyTargetCount) {
        while (GPT_subtitleHistory.length() > shrinkTargetCount) {
            GPT_subtitleHistory.removeAt(0);
            if (GPT_translationHistory.length() > 0)
                GPT_translationHistory.removeAt(0);
        }
    }

    string sourceLabel = (SrcLang == "" ? "Auto Detect" : SrcLang);
    string targetLangCode = DstLang;
    string targetLabel = targetLangCode;

    // 提示词针对字幕场景精简重写：口语优先、短小可读、语气对齐、不审查；
    // 小参数模型上下文有限，规则宁短勿长
    string systemMsg =
        "You are a professional subtitle translator. Translate each subtitle line from "
        + sourceLabel + " into " + targetLabel + ".\n\n"
        "Rules:\n"
        "1. Output ONLY the translation of the last user message: no quotes, no explanations, no notes, no romanization.\n"
        "2. Calibrate intensity to the source: explicit or sexual source lines must be translated with direct, plainly sexual " + targetLabel + " vocabulary — never euphemized, never replaced with vague, clinical or textbook terms, and no cruder than the source. To pick each word, ask which form of the word appears in " + targetLabel + " adult-video subtitles: use that one, never the form used in news reports or medical textbooks. If the source is mild or polite, keep the translation equally mild.\n"
        "3. Sound like natural spoken " + targetLabel + " — how a native speaker would actually say it. Prefer idiomatic equivalents over word-for-word literal rendering.\n"
        "4. Stay as concise as the source; a subtitle must be readable in one glance.\n"
        "5. Match the speaker's tone and register (casual, formal, sarcastic, emotional); keep interjections and sentence-final particles where natural.\n"
        "6. Keep proper nouns, honorifics, numbers and recurring terms accurate and consistent.\n"
        "7. Earlier user/assistant message pairs are previous subtitles for context only — never translate or repeat them.\n";

    // 可选语域锚点：只对源文本身露骨的句子生效，绝不构成对解剖词的全局禁令
    if (GPT_explicit_vocab_hint.length() > 0)
    {
        systemMsg +=
            " When a source line is itself explicit, take the words for body parts and sex acts ONLY from this list: "
            + GPT_explicit_vocab_hint
            + ". Never use any sexual word outside the list — no milder, cuter, jokey, clinical or textbook alternatives. Other explicit vocabulary (fluids, moans, intensity) should also match the register of this list. Medical, documentary or otherwise non-sexual lines always use normal correct terminology.\n";
    }

    string userMsg = Text;

    bool isOpenAIOfficial = IsOpenAIOfficialApiUrl(GPT_apiUrl);
    bool isGeminiApi = IsGeminiApiUrl(GPT_apiUrl);
    bool enableOpenAIPromptCacheControls = isOpenAIOfficial;
    string promptCacheRetention = isOpenAIOfficial ? NormalizePromptCacheRetention(GPT_prompt_cache_retention) : "";
    string promptCacheKey = isOpenAIOfficial ? BuildPromptCacheKey(GPT_selected_model, sourceLabel, targetLabel) : "";

    string requestData = BuildChatPayload(
        GPT_selected_model,
        systemMsg,
        userMsg,
        enableOpenAIPromptCacheControls,
        promptCacheKey,
        promptCacheRetention,
        isGeminiApi,
        GPT_gemini_cached_content,
        contextMessages
    );

    string headers = BuildAuthHeaders(GPT_api_key);
    int delayInt = ParseInt(GPT_delay_ms);
    int retryModeInt = ParseInt(GPT_retry_mode);

    string cacheSessionKey = GPT_context_cache_mode + "|" + GPT_apiUrl + "|" + GPT_selected_model + "|" + promptCacheRetention + "|" + GPT_gemini_cached_content;
    if (cacheSessionKey != GPT_context_cache_disable_key)
        GPT_context_cache_disabled_for_session = false;
    GPT_context_cache_disable_key = cacheSessionKey;

    string translation = "";
    string response = "";

    // Unified Retry Loop: Handles Network, API Errors, and Hallucinations
    int maxRetries = GetRetryLoopLimit(retryModeInt);

    int attempts = 0;

    while (attempts <= maxRetries) {
        if (attempts > 0) {
            if (delayInt > 0) HostSleep(delayInt);
        }

        translation = "";
        response = "";

        // Try Context Caching first if enabled
        if (GPT_context_cache_mode != "off" && !GPT_context_cache_disabled_for_session && ShouldTryResponsesEndpoint(GPT_apiUrl)) {
            string responsesUrl = DeriveResponsesUrl(GPT_apiUrl);
            string cacheFailure = "";
            if (responsesUrl != "") {
                translation = TranslateWithResponses(responsesUrl, headers, GPT_selected_model, systemMsg, Text, promptCacheKey, promptCacheRetention, cacheFailure);
            } else {
                cacheFailure = "Unable to resolve responses endpoint from current API URL.";
            }
            if (translation != "") {
                            // Check for Hallucination
                            if (GPT_check_hallucination == "1" && IsOverlongTranslation(translation, Text)) {
                                HostPrintUTF8("Hallucination detected (Length > 5x). Retrying...\n");
                                attempts++;
                                continue; 
                            }                break; // Success
            }

            if (!GPT_context_cache_disabled_for_session) {
                string fallbackMessage = cacheFailure == "" ? "Context caching failed." : "Context caching failed: " + cacheFailure;
                if (ShouldDisableContextCacheForSession(cacheFailure)) {
                    // Permanent capability errors should disable responses attempts for this session.
                    GPT_context_cache_disabled_for_session = true;
                    HostPrintUTF8(fallbackMessage + "\nUsing chat completions for this session.\n");
                } else {
                    HostPrintUTF8(fallbackMessage + "\nUsing chat completions for this request.\n");
                }
            }
        }

        // Standard Chat Completion
        response = ExecuteSimple(GPT_apiUrl, headers, requestData);

        if (response == "") {
             // Network failure
             attempts++;
             continue;
        }

        JsonReader Reader;
        JsonValue Root;
        if (!Reader.parse(response, Root)) {
            HostPrintUTF8("Failed to parse API response.\n");
            attempts++;
            continue;
        }

        JsonValue choices = Root["choices"];
        if (choices.isArray() && choices.size() > 0 &&
            choices[0].isObject() &&
            choices[0]["message"].isObject() &&
            choices[0]["message"]["content"].isString()) {
            translation = choices[0]["message"]["content"].asString();
            
                        // Check for Hallucination
                        if (GPT_check_hallucination == "1" && IsOverlongTranslation(translation, Text)) {
                            HostPrintUTF8("Hallucination detected (Length > 5x). Retrying...\n");
                            attempts++;
                            continue; 
                        }
            break; // Success
        } else if (Root.isObject() &&
                   Root["error"].isObject() &&
                   Root["error"]["message"].isString()) {
            string errorMessage = Root["error"]["message"].asString();
            HostPrintUTF8("API Error: " + errorMessage + "\n");
            string loweredError = ToLower(errorMessage);
            if (enableOpenAIPromptCacheControls && loweredError.find("prompt_cache") != -1) {
                enableOpenAIPromptCacheControls = false;
                requestData = BuildChatPayload(
                    GPT_selected_model,
                    systemMsg,
                    userMsg,
                    false,
                    promptCacheKey,
                    promptCacheRetention,
                    isGeminiApi,
                    GPT_gemini_cached_content,
                    contextMessages
                );
                HostPrintUTF8("Prompt cache control fields are unsupported on this endpoint. Retrying without them.\n");
            }
             // API returned an error (e.g. rate limit, context length). 
             // Should we retry? Usually yes for rate limits, maybe no for invalid request.
             // For simplicity and robustness, we retry.
            attempts++;
            continue;
        } else {
            HostPrintUTF8("Translation failed. Unknown response format.\n");
            attempts++;
            continue;
        }
    }

    if (translation == "") {
         string failureMessage = "Translation failed after retries.";
         if (response != "") failureMessage += " Last response: " + response;
         HostPrintUTF8(failureMessage + "\n");
         return FormatFailureTranslation(response, "Translation failed. Check settings and network.");
    }

    // 先剥掉模型输出的包装（引号/前导语），再判空、入历史
    translation = CleanTranslationOutput(translation);
    if (translation == "") {
        HostPrintUTF8("Model returned an empty or wrapper-only response.\n");
        return FormatFailureTranslation(response, "Translation failed. Model returned no usable content.");
    }

    // 源文与译文成对入历史，作为后续行的 user/assistant 上下文
    GPT_subtitleHistory.insertLast(Text);
    GPT_translationHistory.insertLast(translation);

    bool isFailureTranslation = translation.length() >= GPT_CTX_TRANSLATION_FAILURE_WARNING_PREFIX.length() &&
                                translation.substr(0, GPT_CTX_TRANSLATION_FAILURE_WARNING_PREFIX.length()) == GPT_CTX_TRANSLATION_FAILURE_WARNING_PREFIX;

    if (!isFailureTranslation && GPT_selected_model.find("gemini") != -1) {
        while (translation.length() > 0 && translation.substr(translation.length() - 1, 1) == "\n") {
            translation = translation.substr(0, translation.length() - 1);
        }
    }
    if (!isFailureTranslation && (targetLangCode == "fa" || targetLangCode == "ar" || targetLangCode == "he")) {
        string UNICODE_RLE = "\u202B";
        translation = UNICODE_RLE + translation;
    }
    SrcLang = "UTF8";
    DstLang = "UTF8";
    string result = TrimTrailingPunctuation(translation);
    // 缓存存最终形态（含 RTL 前缀、已去尾标点），命中时直接返回
    StoreTranslationCache(cacheKey, result);
    return result;
}

string FormatFailureTranslation(const string &in rawResponse, const string &in fallbackMessage) {
    string detail = rawResponse.Trim();
    if (detail == "")
        detail = fallbackMessage;
    return GPT_CTX_TRANSLATION_FAILURE_WARNING_PREFIX + detail;
}

// Plugin Initialization
void OnInitialize() {
    HostPrintUTF8("ChatGPT translation plugin loaded.\n");
    RefreshConfiguration();
    GPT_context_cache_disabled_for_session = false;
    GPT_context_cache_disable_key = "";
    if (GPT_api_key != "") {
        HostPrintUTF8("Saved API Key, model name, and API URL loaded.\n");
    }
}

// Plugin Finalization
void OnFinalize() {
    HostPrintUTF8("ChatGPT translation plugin unloaded.\n");
}
string ToLower(const string &in s) {
    return s.MakeLower();
}

string NormalizeCacheMode(const string &in mode) {
    string trimmed = mode.Trim();
    if (trimmed == "")
        return "auto";
    string lower = ToLower(trimmed);
    if (lower == "off" || lower == "disable" || lower == "disabled" || lower == "chat")
        return "off";
    return "auto";
}

string NormalizePromptCacheRetention(const string &in retention) {
    string trimmed = retention.Trim();
    if (trimmed == "")
        return "";
    string lower = ToLower(trimmed);
    if (lower == "24h")
        return "24h";
    if (lower == "in_memory" || lower == "in-memory" || lower == "memory" || lower == "mem" || lower == "default")
        return "in-memory";
    return "";
}

bool IsOpenAIOfficialApiUrl(const string &in apiUrl) {
    return ToLower(apiUrl).find("api.openai.com") != -1;
}

bool IsGeminiApiUrl(const string &in apiUrl) {
    string lower = ToLower(apiUrl);
    return lower.find("generativelanguage.googleapis.com") != -1;
}

bool ShouldTryResponsesEndpoint(const string &in apiUrl) {
    if (IsGeminiApiUrl(apiUrl))
        return false;
    return true;
}

bool ShouldDisableContextCacheForSession(const string &in failureReason) {
    string lower = ToLower(failureReason.Trim());
    if (lower == "")
        return false;
    if (lower.find("404") != -1 || lower.find("not found") != -1)
        return true;
    if (lower.find("unsupported") != -1 || lower.find("does not support") != -1)
        return true;
    if (lower.find("unknown parameter") != -1 || lower.find("unrecognized") != -1 || lower.find("invalid parameter") != -1)
        return true;
    if (lower.find("no response from responses endpoint") != -1)
        return true;
    if (lower.find("route") != -1 || lower.find("endpoint") != -1 || lower.find("responses endpoint") != -1)
        return true;
    return false;
}

string BuildPromptCacheKey(const string &in modelName, const string &in sourceLang, const string &in targetLang) {
    string key = "potplayer_subtitle_translate_v2";
    string model = ToLower(modelName.Trim());
    string src = ToLower(sourceLang.Trim());
    string dst = ToLower(targetLang.Trim());
    if (model != "")
        key += "|" + model;
    if (src == "")
        src = "auto";
    if (dst == "")
        dst = "auto";
    key += "|" + src + ">" + dst;
    return key;
}

// 温度值校验：仅允许数字与小数点，且至少含一个非零数字（"0"/"0.00" 视为未设置）
bool IsValidTemperature(const string &in s) {
    if (s.length() == 0) return false;
    bool hasNonZero = false;
    for (uint i = 0; i < s.length(); i++) {
        uint8 c = s[i];
        if (c >= 48 && c <= 57) {
            if (c != 48) hasNonZero = true;
        } else if (c != 46) { // '.'
            return false;
        }
    }
    return hasNonZero;
}

string BuildChatPayload(
    const string &in modelName,
    const string &in systemMsg,
    const string &in userMsg,
    bool includePromptCacheControls,
    const string &in promptCacheKey,
    const string &in promptCacheRetention,
    bool includeGeminiCachedContent,
    const string &in geminiCachedContent,
    const string &in contextMessages
) {
    string escapedSystem = JsonEscape(systemMsg);
    string escapedUser = JsonEscape(userMsg);
    // 组装字段；模型名留空时不发送 model 字段（LM Studio 等本地服务端会选用当前
    // 加载的模型）。第一个字段不能带前导逗号：model 被省略时 payload 以 "{" 开头
    bool firstField = true;
    string payload = "{";
    if (modelName.Trim() != "") {
        payload += "\"model\":\"" + JsonEscape(modelName) + "\"";
        firstField = false;
    }

    // 采样温度：非法值不发送，交由服务端默认
    string temperature = GPT_api_temperature.Trim();
    if (IsValidTemperature(temperature)) {
        payload += (firstField ? "" : ",") + "\"temperature\":" + temperature;
        firstField = false;
    }

    string cacheKey = promptCacheKey.Trim();
    if (includePromptCacheControls && cacheKey != "") {
        payload += (firstField ? "" : ",") + "\"prompt_cache_key\":\"" + JsonEscape(cacheKey) + "\"";
        firstField = false;
    }

    // 调用方（ServerLogin/Translate）已做过归一化，这里不再重复 Normalize
    if (includePromptCacheControls && promptCacheRetention != "") {
        payload += (firstField ? "" : ",") + "\"prompt_cache_retention\":\"" + JsonEscape(promptCacheRetention) + "\"";
        firstField = false;
    }

    // 消息顺序：system → 上下文(前文/前译 user/assistant 对) → 当前待翻译行
    payload += (firstField ? "" : ",") + "\"messages\":[{\"role\":\"system\",\"content\":\"" + escapedSystem + "\"},"
             + contextMessages
             + "{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}]";
    firstField = false;

    string cachedContent = geminiCachedContent.Trim();
    if (includeGeminiCachedContent && cachedContent != "")
        payload += ",\"google\":{\"cached_content\":\"" + JsonEscape(cachedContent) + "\"}";

    payload += "}";
    return payload;
}

void EnsureTokenRulesLoaded() {
    if (GPT_token_rules_initialized)
        return;
    GPT_token_rules_initialized = true;
    GPT_default_model_token_limit = 4096;
    GPT_token_rule_types.resize(0);
    GPT_token_rule_values.resize(0);
    GPT_token_rule_limits.resize(0);

    JsonReader reader;
    JsonValue root;
    if (!reader.parse(GPT_pre_model_token_limits_json, root))
        return;
    if (!root.isObject())
        return;

    if (root["default"].isInt())
        GPT_default_model_token_limit = root["default"].asInt();
    else if (root["default"].isString()) {
        int parsedDefault = ParseInt(root["default"].asString());
        if (parsedDefault > 0)
            GPT_default_model_token_limit = parsedDefault;
    }

    JsonValue rulesNode = root["rules"];
    if (!rulesNode.isArray())
        return;

    int count = rulesNode.size();
    for (int i = 0; i < count; i++) {
        JsonValue entry = rulesNode[i];
        if (!entry.isObject())
            continue;
        string matchType = "";
        string matchValue = "";
        int limit = 0;
        if (entry["type"].isString())
            matchType = entry["type"].asString();
        if (entry["value"].isString())
            matchValue = entry["value"].asString();
        if (entry["tokens"].isInt())
            limit = entry["tokens"].asInt();
        else if (entry["tokens"].isString())
            limit = ParseInt(entry["tokens"].asString());
        if (matchType != "" && matchValue != "" && limit > 0) {
            GPT_token_rule_types.insertLast(matchType);
            GPT_token_rule_values.insertLast(matchValue);
            GPT_token_rule_limits.insertLast(limit);
        }
    }
}

string DeriveResponsesUrl(const string &in originalUrl) {
    string url = originalUrl.Trim();
    while (url.length() > 0 && url.substr(url.length() - 1, 1) == "/")
        url = url.substr(0, url.length() - 1);
    if (url == "")
        return "";
    if (url.find("/responses") != -1)
        return url;
    int chatPos = url.find("/chat/completions");
    if (chatPos != -1)
        return url.substr(0, chatPos) + "/responses";
    return url + "/responses";
}

string ExecuteSimple(const string &in url, const string &in headers, const string &in payload) {
    return HostUrlGetString(url, GPT_UserAgent, headers, payload);
}

string BuildResponsesPayload(
    const string &in modelName,
    const string &in systemMsg,
    const string &in subtitleText,
    const string &in promptCacheKey,
    const string &in promptCacheRetention
) {
    string escapedSystem = JsonEscape(systemMsg);
    string escapedSubtitle = JsonEscape(subtitleText);
    string payload = "{\"model\":\"" + JsonEscape(modelName) + "\"";
    string cacheKey = promptCacheKey.Trim();
    if (cacheKey != "")
        payload += ",\"prompt_cache_key\":\"" + JsonEscape(cacheKey) + "\"";
    string retention = NormalizePromptCacheRetention(promptCacheRetention);
    if (retention != "")
        payload += ",\"prompt_cache_retention\":\"" + JsonEscape(retention) + "\"";
    payload += ",\"input\":[";
    payload += "{\"role\":\"system\",\"content\":[{\"type\":\"input_text\",\"text\":\"" + escapedSystem + "\"}]}";
    payload += ",{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"" + escapedSubtitle + "\"}]}";
    payload += "]}";
    return payload;
}

string ExtractResponsesText(JsonValue &in root) {
    if (!root.isObject())
        return "";

    JsonValue output = root["output"];
    if (!output.isArray())
        return "";

    int size = output.size();
    for (int i = 0; i < size; i++) {
        JsonValue entry = output[i];
        if (!entry.isObject())
            continue;
        JsonValue content = entry["content"];
        if (!content.isArray())
            continue;
        int csize = content.size();
        for (int j = 0; j < csize; j++) {
            JsonValue part = content[j];
            if (part.isObject()) {
                if (part["type"].isString() && part["type"].asString() == "output_text" && part["text"].isString())
                    return part["text"].asString();
            } else if (part.isString()) {
                return part.asString();
            }
        }
    }
    return "";
}

string TranslateWithResponses(
    const string &in responsesUrl,
    const string &in headers,
    const string &in modelName,
    const string &in systemMsg,
    const string &in subtitleText,
    const string &in promptCacheKey,
    const string &in promptCacheRetention,
    string &out failureReason
) {
    string requestData = BuildResponsesPayload(modelName, systemMsg, subtitleText, promptCacheKey, promptCacheRetention);
    string response = ExecuteSimple(responsesUrl, headers, requestData);
    if (response == "") {
        failureReason = "No response from Responses endpoint.";
        return "";
    }

    JsonReader reader;
    JsonValue root;
    if (!reader.parse(response, root)) {
        failureReason = "Failed to parse Responses API response.";
        return "";
    }

    string translatedText = ExtractResponsesText(root);
    if (translatedText != "") {
        return translatedText;
    }

    if (root.isObject() && root["error"].isObject() && root["error"]["message"].isString()) {
        failureReason = root["error"]["message"].asString();
    } else {
        failureReason = "Responses API returned no usable output.";
    }
    return "";
}

bool IsOverlongTranslation(const string &in translation, const string &in original) {
    if (original.length() == 0) return false;
    return translation.length() > (original.length() * 5);
}
