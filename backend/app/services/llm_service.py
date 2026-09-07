import os
import logging
from typing import Optional, Dict, Any, List
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("talentloq.llm")

# Verified 100% Free Models
FREE_GROQ_MODELS = ["llama-3.1-8b-instant", "qwen/qwen3.8-27b", "groq/compound-mini"]
FREE_OPENROUTER_MODELS = [
    "qwen/qwen-2.5-coder-32b-instruct:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "deepseek/deepseek-r1:free",
    "google/gemma-2-9b-it:free",
]
FREE_MISTRAL_MODELS = ["mistral-small-latest", "open-mistral-7b"]
FREE_GEMINI_MODELS = ["gemini-2.0-flash-lite", "gemini-flash-latest"]

class LLMService:
    """
    Unified Multi-Provider Free-Tier LLM Service for TalentLOQ.
    Configured exclusively with verified free-tier models with automatic failover.
    """
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(LLMService, cls).__new__(cls)
            cls._instance._init_clients()
        return cls._instance

    def _init_clients(self):
        self.groq_key = os.environ.get("GROQ_API_KEY", "").strip()
        self.openrouter_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
        self.gemini_key = os.environ.get("GEMINI_API_KEY", os.environ.get("GOOGLE_API_KEY", "")).strip()
        self.mistral_key = os.environ.get("MISTRAL_API_KEY", "").strip()

        # 1. Groq (Free Tier)
        self.groq_client = None
        if self.groq_key and not self.groq_key.startswith("your_"):
            try:
                from openai import OpenAI
                self.groq_client = OpenAI(base_url="https://api.groq.com/openai/v1", api_key=self.groq_key)
                logger.info("Groq free-tier client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Groq client: {e}")

        # 2. OpenRouter (Free Tier :free models)
        self.openrouter_client = None
        if self.openrouter_key and not self.openrouter_key.startswith("your_"):
            try:
                from openai import OpenAI
                self.openrouter_client = OpenAI(base_url="https://openrouter.ai/api/v1", api_key=self.openrouter_key)
                logger.info("OpenRouter free-tier client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize OpenRouter client: {e}")

        # 3. Mistral (Free Tier)
        self.mistral_client = None
        if self.mistral_key and not self.mistral_key.startswith("your_"):
            try:
                from mistralai import Mistral
                self.mistral_client = Mistral(api_key=self.mistral_key)
                logger.info("Mistral free client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Mistral client: {e}")

        # 4. Gemini (Google AI Studio Free Tier)
        self.gemini_client = None
        if self.gemini_key and not self.gemini_key.startswith("your_"):
            try:
                from google import genai
                self.gemini_client = genai.Client(api_key=self.gemini_key)
                logger.info("Gemini free client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Gemini client: {e}")

    @staticmethod
    def _print_token_usage(provider: str, model: str, prompt_tokens: int, completion_tokens: int, total_tokens: int) -> Dict[str, int]:
        print(
            f"\n\033[1;36m+==================== [AI API TOKEN USAGE] ====================+\033[0m\n"
            f"  \033[1mProvider:\033[0m          {provider.upper()}\n"
            f"  \033[1mModel:\033[0m             {model}\n"
            f"  \033[1;33mPrompt Tokens:\033[0m     {prompt_tokens:,}\n"
            f"  \033[1;32mCompletion Tokens:\033[0m {completion_tokens:,}\n"
            f"  \033[1;35mTotal Tokens Used:\033[0m {total_tokens:,}\n"
            f"\033[1;36m+==============================================================+\033[0m\n",
            flush=True
        )
        logger.info(
            "[AI Token Usage] Provider: %s | Model: %s | Prompt: %d | Completion: %d | Total: %d",
            provider, model, prompt_tokens, completion_tokens, total_tokens
        )
        return {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        }

    async def generate(self, prompt: str, system_prompt: Optional[str] = None, max_tokens: int = 500) -> Dict[str, Any]:
        """
        Executes generation strictly through free models across available providers.
        Priority: Groq (Free) -> OpenRouter (:free) -> Mistral (Free) -> Gemini (Free).
        """
        errors = []

        # 1. Try Groq Free Tier
        if self.groq_client:
            for model_name in FREE_GROQ_MODELS:
                try:
                    messages = []
                    if system_prompt:
                        messages.append({"role": "system", "content": system_prompt})
                    messages.append({"role": "user", "content": prompt})
                    res = self.groq_client.chat.completions.create(
                        model=model_name,
                        messages=messages,
                        max_tokens=max_tokens,
                    )
                    text = res.choices[0].message.content.strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    tokens_dict = self._print_token_usage("groq", model_name, p_tok, c_tok, t_tok)

                    return {
                        "text": text,
                        "provider": "groq",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": False,
                        "tokens_used": tokens_dict,
                    }
                except Exception as e:
                    logger.warning(f"Groq {model_name} failed: {e}")
                    errors.append(f"Groq ({model_name}): {e}")

        # 2. Try OpenRouter :free Models
        if self.openrouter_client:
            for model_name in FREE_OPENROUTER_MODELS:
                try:
                    messages = []
                    if system_prompt:
                        messages.append({"role": "system", "content": system_prompt})
                    messages.append({"role": "user", "content": prompt})
                    res = self.openrouter_client.chat.completions.create(
                        model=model_name,
                        messages=messages,
                        max_tokens=max_tokens,
                    )
                    text = res.choices[0].message.content.strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    tokens_dict = self._print_token_usage("openrouter", model_name, p_tok, c_tok, t_tok)

                    return {
                        "text": text,
                        "provider": "openrouter",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                    }
                except Exception as e:
                    logger.warning(f"OpenRouter {model_name} failed: {e}")
                    errors.append(f"OpenRouter ({model_name}): {e}")

        # 3. Try Mistral Free
        if self.mistral_client:
            for model_name in FREE_MISTRAL_MODELS:
                try:
                    messages = []
                    if system_prompt:
                        messages.append({"role": "system", "content": system_prompt})
                    messages.append({"role": "user", "content": prompt})
                    res = self.mistral_client.chat.complete(
                        model=model_name,
                        messages=messages,
                        max_tokens=max_tokens,
                    )
                    text = res.choices[0].message.content.strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    tokens_dict = self._print_token_usage("mistral", model_name, p_tok, c_tok, t_tok)

                    return {
                        "text": text,
                        "provider": "mistral",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                    }
                except Exception as e:
                    logger.warning(f"Mistral {model_name} failed: {e}")
                    errors.append(f"Mistral ({model_name}): {e}")

        # 4. Try Gemini Free Tier
        if self.gemini_client:
            for model_name in FREE_GEMINI_MODELS:
                try:
                    full_content = f"{system_prompt}\n\n{prompt}" if system_prompt else prompt
                    res = self.gemini_client.models.generate_content(
                        model=model_name,
                        contents=full_content,
                    )
                    text = res.text.strip()
                    usage = getattr(res, "usage_metadata", None)
                    p_tok = int(getattr(usage, "prompt_token_count", 0) or 0)
                    c_tok = int(getattr(usage, "candidates_token_count", 0) or 0)
                    t_tok = int(getattr(usage, "total_token_count", 0) or (p_tok + c_tok))
                    tokens_dict = self._print_token_usage("gemini", model_name, p_tok, c_tok, t_tok)

                    return {
                        "text": text,
                        "provider": "gemini",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                    }
                except Exception as e:
                    logger.warning(f"Gemini {model_name} failed: {e}")
                    errors.append(f"Gemini ({model_name}): {e}")

        return {
            "text": "All free AI models are currently unavailable.",
            "provider": "none",
            "model": "none",
            "is_free": True,
            "fallback_used": True,
            "errors": errors,
        }

llm_service = LLMService()
