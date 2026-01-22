## DateCraft — Backend Architecture Sample (Ruby on Rails)

This repository is a public backend architecture sample extracted from my private project DateCraft, an AI-assisted Ruby on Rails application that generates personalized date suggestions based on user preferences such as budget, location, interests, and constraints.

The full DateCraft repository is private because it is an active product and contains sensitive configuration, credentials, and business logic. This sample repo is intended to demonstrate my backend engineering approach, including request flow design, service-oriented architecture, AI integration, background jobs, and testing practices.

⸻

## Project Overview

At a high level, DateCraft:
	•	Authenticates users using Devise
	•	Stores structured preference data via user profiles
	•	Generates personalized date suggestions using deterministic rules combined with AI-assisted generation
	•	Supports asynchronous workflows via ActiveJob with Sidekiq

⸻

## What’s Included in This Sample

This repository focuses on a small but representative slice of the backend:
	•	Controller flow
Demonstrates how incoming HTTP requests are validated and delegated to the service layer
(app/controllers/date_suggestions_controller.rb)
	•	Core service logic
Centralized business logic for generating date suggestions
(app/services/date_suggestion_service.rb)
	•	AI integration
Example of calling OpenAI’s GPT-4o-mini API with structured prompts while enforcing constraints
	•	Background jobs
Asynchronous processing using ActiveJob with Sidekiq
(app/jobs/date_reminder_job.rb)
	•	Models
Domain modeling with validations and relationships
(app/models/user.rb, user_profile.rb, date_suggestion.rb)
	•	Tests
RSpec tests validating service behavior and request flow

⸻

## Architecture Overview

The application is intentionally structured to keep controllers thin and business logic isolated within service objects.

High-level flow:
	1.	Incoming request is received by the controller
	2.	Inputs are validated and normalized
	3.	Core logic is delegated to DateSuggestionService
	4.	Constraints are applied deterministically
	5.	AI-assisted generation is invoked only after validation
	6.	Results are persisted and returned to the client

Key design principles:
	•	Separation of concerns: controller → service → model
	•	Deterministic before generative: enforce constraints before invoking AI
	•	Testability: business logic isolated from HTTP concerns
	•	Scalability: background jobs for non-blocking workflows
	•	Maintainability: small, focused classes with explicit responsibilities

⸻

## AI Usage and Decision-Making

AI is used as a controlled component, not as the source of truth.
	•	Prompts are structured and contextualized using validated user data
	•	AI output is parsed and handled defensively
	•	Results are checked for consistency before being persisted
	•	When AI output does not align with constraints or introduces noise, the logic favors simpler, deterministic behavior

During development, AI tools were also used to brainstorm approaches and refactor ideas. All generated suggestions were reviewed, validated against documentation, and modified to fit Rails conventions and architectural boundaries.

⸻

## Testing

This sample uses RSpec to validate correctness and prevent regressions.
	•	spec/services/date_suggestion_service_spec.rb
Verifies core business logic, including validation flow, prompt construction, and response handling
	•	spec/requests/date_suggestions_spec.rb
Validates end-to-end request behavior from HTTP input to response output

External AI calls are stubbed so tests are deterministic, fast, and do not require real credentials or network access.

⸻

## Why This Repo Is a Sample

The complete DateCraft application is private because it contains:
	•	Production credentials and configuration
	•	Third-party service integrations
	•	Proprietary business logic

This public repository is intentionally scoped to showcase architecture, decision-making, and engineering practices without exposing sensitive information.

⸻

## Links

GitHub organization:
https://github.com/DateCraft

Private main repository:
https://github.com/DateCraft/DateCraft

Public backend architecture sample:
https://github.com/hcogden/datecraft-backend-architecture-sample/tree/main

⸻

## Final note

This repository reflects how I approach backend engineering: prioritize correctness and clarity, design for testability, integrate AI responsibly, and build systems that can evolve without becoming difficult to reason about.
