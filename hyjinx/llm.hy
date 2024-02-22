"
A Large Language Model in your repl.

APIs and utilities for interacting with a Large Language Model (LLM)
assistant in Hylang.

This module provides functions to interact with a Large Language Model
assistant for various tasks such as generating code comments,
providing explanations, performing code review, and rewriting code.
It includes a Hy implementation of a TabbyClient to interact with
TabbyAPI for model management and streaming completions.

Features:
- converse: Chat over a list of messages, updating the message list in-place.
- definstruct: Create methods for instructing over python/hy objects.
- instruct: Generic instruction method for the assistant.
- TabbyClient: Implementation of a client to interact with TabbyAPI for model management and
  streaming completions.

Functions:
- `converse`: Chat over a list of messages and update in-place the message list.
- `definstruct`: A macro to create functions for specific tasks like
  comments, docstrings, explanations, review, rewrite, and test
  (these examples have been implemented)
- `instruct`: Generic instruction method for the assistant.
- Various methods for managing TabbyAPI servers, such as loading models, templates, LoRAs
  and configuring the client.

The TabbyClient class:
- `models`: List all models available to TabbyAPI or OpenAI.
- `model-load`: Set the currently loaded model (TabbyAPI).
- `model-unload`: Unload the currently loaded model (TabbyAPI).
- `templates`: List all templates available to TabbyAPI.
- `template-load`: Set the currently loaded template (TabbyAPI).
- `template-unload`: Unload the currently loaded template (TabbyAPI).
- `loras`: List all LoRAs available to TabbyAPI.
- `lora-load`: Load LoRAs when using TabbyAPI.
- `lora-unload`: Unload LoRA when using TabbyAPI.

"

(require hyrule [-> ->> unless of])
(require hyjinx.macros [defmethod])

(import hyrule [pformat])
(import hyjinx.lib [first last hash-color])
(import hyjinx.source [get-source get-source-details])

(import httpx shutil)
(import types [ModuleType FunctionType MethodType TracebackType])
(import itertools [tee])
(import openai [OpenAI])
(import json.decoder [JSONDecodeError])
(import pansi [ansi :as _ansi])


(defclass TabbyClientError [Exception])
(defclass ChatError [Exception])

(setv HasCodeType (| type ModuleType FunctionType MethodType TracebackType))

;; * the actually useful functions 
;; -----------------------------------------------------------------------------

(defmethod converse [#^ OpenAI client #^ (of list dict) messages #^ str content *
                     [system-prompt "You are an intelligent and concise assistant."]
                     [max-tokens 1000]
                     [color None]
                     #** kwargs]
  "Chat over a list of messages and update in-place the message list.
  The system prompt is injected each call so can be changed.

  You might use this function like:
  (setv _messages [])
  (setv chat (partial converse tabby _messages))
  (chat \"Hello there.\")"
  (let [sys (_system system-prompt)
        usr (_user content)
        width (.pop kwargs "width" None)
        margin (.pop kwargs "margin" "    ")
        [output-1 output-2] (tee (_completion
                                   client
                                   [sys #* messages usr]
                                   :max-tokens max-tokens
                                   #** kwargs))]
    (_output output-1
             :print True
             :width width
             :margin margin
             :color (or color (hash-color (or client.model ""))))
    (.append messages usr)
    (.append messages (_assistant (_output output-2 :print False)))))

(defmacro definstruct [f prompt]
  "Create a function that instructs over a python/hy object."
  `(defn ~f [client obj * [print True] #** kwargs]
     ~prompt
     (instruct client
              ~prompt
              obj
              :print print
              #** kwargs)))

(defmethod instruct [#^ OpenAI client #^ str prompt *
                     [print True]
                     [margin "  "]
                     [width None]
                     [system-prompt "You are an intelligent and concise assistant."]
                     [max-tokens 1000]
                     [color _ansi.reset]
                     #** kwargs]
  "Just ask a general instruction or question, no object, no chat."
  (let [sys (_system system-prompt)
        usr (_user prompt)
        stream (_completion client [sys usr] :max-tokens max-tokens #** kwargs)]
    (_output stream :print print :width width :margin margin :color color)))

(defmethod instruct [#^ OpenAI client #^ str prompt #^ HasCodeType obj *
                     [print True]
                     [margin "  "]
                     [width None]
                     [system-prompt  "You are an intelligent, expert and concise senior programmer."]
                     [max-tokens 1000]
                     [color _ansi.reset]
                     #** kwargs]
  "Instruct a hy or python object's source code."
  (let [details (get-source-details obj)
        language (:language details)
        source (get-source obj)
        sys (_system system-prompt)
        usr (_user f"You will be shown code for {obj} (module {(:module details)}). It is in the {language} language.
{prompt}

{source}")
        stream (_completion client [sys usr] :max-tokens max-tokens #** kwargs)]
    (_output stream :print print :width width :margin margin :color color)))

(definstruct comments "Rewrite the following code, with high-quality comments.")

(definstruct docstring "Write a high-quality docstring for the following code.")

(definstruct explain "Clearly explain the purpose of the following code.")

(definstruct review "Write a clear, high-quality peer-review of the following code. Identify any bugs, logic errors, and overlooked edge cases. Briefly explain your reasoning. Concentrate on the most important points first.")

(definstruct rewrite "Rewrite the following code in the same language, improving quality and clarity. Briefly state what you will do before giving the rewritten code.")

(definstruct test "Write a high-quality test for the following code.")

;; * message convenience functions
;; -----------------------------------------------------------------------------

(defn _msg [#^ str role
            #^ str content]
  "Just a simple dict with the needed fields."
  (if content
      {"role" role
       "content" (.strip content)}
      (raise (ChatError f"No content in message (role: {role})."))))

(defn _system [#^ str content]
  (_msg "system" content))

(defn _user [#^ str content]
  (_msg "user" content))

(defn _assistant [#^ str content]
  (_msg "assistant" content))

;; * output handling
;; -----------------------------------------------------------------------------

(defn _output [stream * [print True] #** kwargs]
  (if print
      (_print-stream stream #** kwargs)
      (.join "" (lfor chunk stream :if (-> chunk.choices
                                            (first)
                                            (getattr "delta")
                                            (getattr "content"))
                      (let [choice (first chunk.choices)
                            content choice.delta.content]
                        content)))))

(defn _print-stream [stream * [width None] [margin "  "] [color _ansi.reset]]
  "Print a streaming chat completion."
  (let [term (shutil.get-terminal-size)
        w (if width (min width (- term.columns 5))
                    (- term.columns 5))]     
    (setv line "")
    (print margin :end color)
    (for [chunk stream :if (-> chunk.choices
                                (first)
                                (getattr "delta")
                                (getattr "content"))]
      (let [choice (first chunk.choices)
            content choice.delta.content]
        (+= line content)
        (cond (.endswith content "\n")
              (do
                (print f"{content}{margin}" :end "")
                (setv line ""))

              (> (+ (len line) (len margin)) w)
              (do (print f"\n{margin}{(.strip content)}" :end "")
                  (setv line (.strip content)))

              :else
              (print content :end "" :flush True))))
    (print _ansi.reset)))

;; * the Tabby API client
;; ----------------------------------------------------

(defclass TabbyClient [OpenAI]
  "A REPL-facing client for TabbyAPI (https://github.com/theroyallab/tabbyAPI)."

  (defn __init__ [self #** kwargs]
    "The base-url should have the 'v1' at the end.
     Initialise as for OpenAI, but optionally pass admin_key as well."
    (setv self.model None)
    (setv self.admin_key (.pop kwargs "admin_key" None))
    (.__init__ (super) #** kwargs))

  (defn _get [self endpoint]
    "GET an authenticated endpoint or raise error."
    (let [response (httpx.get (.join self.base-url endpoint)
                              :headers {"x-api-key" self.api-key})]
      (if response.is-success
          (response.json)
          (raise (TabbyClientError f"{_ansi.red}{response.status-code}\n{(pformat (:detail (response.json)) :indent 2)}{_ansi.reset}")))))

  (defn _post [self endpoint * [admin False] #** data]
    "POST to an authenticated endpoint or raise error."
    (let [auth (if admin
                   {"x-admin-key" self.admin-key}
                   {"x-api-key" self.api-key})
          response (httpx.post (.join self.base-url endpoint)
                               :headers auth
                               :json (or data {}))]
      (if response.is-success
          (try
            (.json response)
            (except [e [JSONDecodeError TypeError]]
              response))
          (raise (TabbyClientError f"{_ansi.red}{response.status-code}\n{(pformat (:detail (response.json)) :indent 2)}{_ansi.reset}"))))))

;; * generation methods requiring user authentication
;; ----------------------------------------------------

(defmethod _completion [#^ OpenAI client messages * [stream True] #** kwargs]
  "Generate a streaming completion using the chat completion endpoint.
  In python, use as
        for chunk in stream:
            print(chunk.choices[0].delta.content or '', end='') "
  (client.chat.completions.create
    :model (.pop kwargs "model" (getattr client "model" "gpt-4-turbo-preview"))
    :messages messages
    :stream stream
    #** kwargs))

;; * methods requiring user authentication
;; ----------------------------------------------------

(defmethod models [#^ TabbyClient client]
  "List all models available to TabbyAPI."
  (let [l (:data (client._get "models"))]
    (sorted (lfor m l (:id m)))))

(defmethod loras [#^ TabbyClient client]
  "List all loras available to TabbyAPI."
  (let [loras (:data (client._get "loras"))]
    (sorted (lfor l loras {"name" (:id l) #** l})
            :key :name)))

(defmethod models [#^ OpenAI client]
  "List all models available to OpenAI."
  (let [models (client.models.list)]
    (lfor m models m.id)))

(defmethod model [#^ TabbyClient client]
  "Get the currently loaded model."
  (client._get "model"))
    
(defmethod lora [#^ TabbyClient client]
  "Get the currently loaded loras."
  (client._get "lora"))

(defmethod templates [#^ TabbyClient client]
  "List all templates available to TabbyAPI."
  (sorted (:data (client._get "templates"))))

;; * methods requiring admin authentication
;; ----------------------------------------------------

(defmethod template-load [#^ TabbyClient client #^ str template]
  "Set the currently loaded template."
  (client._post "template/switch"
                :admin True
                :name template))

(defmethod template-unload [#^ TabbyClient client]
  "Unload the currently loaded template."
  (client._post "template/unload"
                :admin True))

(defmethod model-load [#^ OpenAI client #^ str model #** kwargs]
  "Set the OpenAI model to use for completions.
  The OpenAI class expects the model to be specified in completions, so this sets a default."
  (setv client.model model))

(defmethod model-load [#^ TabbyClient client #^ str model #** kwargs]
  "Load a model.
  TabbyAPI needs to load/unload models before use.
  kwargs are passed to the API.
  See the TabbyAPI docs for valid keys and values."
  ;; TODO : steam response to show progress
  (let [response (client._post "model/load" :admin True :name model #** kwargs)]
    (setv client.model model)
    (print f"{model} loaded.")))

(defmethod model-unload [#^ TabbyClient client]
  "Unload a model.
   TabbyAPI needs to load/unload models before use."
  (client._post "model/unload"
                :admin True)
  (setv client.model None))

(defmethod lora-load [#^ TabbyClient client #^ list loras]
  "Load LoRAs when using TabbyAPI.
  loras is a list of dicts, with 'name', 'scaling' as keys."
  (client._post "lora/load"
                :admin True
                :loras loras))
    
(defmethod lora-unload [#^ TabbyClient client]
  "Unload LoRAs when using TabbyAPI."
  (client._post "lora/unload"
                :admin True))
