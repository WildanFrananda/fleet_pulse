# Enterprise Elixir & Phoenix Development Guide

## 🎯 Core Philosophy
This project strictly follows **Functional Programming** paradigms while maintaining **Enterprise Clean Architecture** standards (similar to patterns found in NestJS, Spring Boot, or Laravel). 
DO NOT force Object-Oriented Programming (OOP) patterns (classes, tight inheritance, state mutation) into this codebase.

## 1. Type Safety (Static Typing Simulation)
Although Elixir is dynamically typed, this project enforces strict type safety using **Typespecs** and **Dialyzer**.
- ALWAYS define `@type` for custom data structures (acting as TypeScript `interface` or Java `class` equivalents).
- ALWAYS use `@spec` to define function inputs and return types.
- Ensure all types are strictly validated before merging into the main branch.

```elixir
# Example of strict typing
@type t :: %__MODULE__{
  id: integer(),
  status: atom(),
  total: float()
}

@spec get_order(integer()) :: {:ok, t()} | {:error, :not_found}
```

## 2. Architecture: Phoenix Contexts (Domain-Driven Design)
Phoenix is treated strictly as the web delivery mechanism. Business logic MUST NOT reside in Controllers or Views.
- **`lib/app_web/` (Web Layer):** Contains Controllers, Routers, and JSON Views. Responsibilities are limited to parsing HTTP/Websocket requests and returning mapped responses.
- **`lib/app/` (Core/Domain Layer):** Contains **Contexts** (independent domain modules). This is the equivalent of the Service Layer.
- **`lib/app/repo.ex` (Data Layer):** Pure Ecto configurations and database interaction.

## 3. OOP to Elixir Equivalency Map
When translating enterprise OOP patterns to this project, adhere to these equivalencies:

| OOP Concept (Nest/Spring) | Elixir / Phoenix Pattern | Implementation Notes |
| :--- | :--- | :--- |
| **Interfaces** | `@behaviour` | Define contracts via `@callback`, implement using `@impl`. |
| **Dependency Injection** | App Config / Args | Pass module dependencies as function arguments or resolve via `Application.get_env/3` (useful for `Mox` testing). |
| **DTOs & Validation** | `Ecto.Changeset` | Use Changesets strictly for casting, validating, and filtering incoming data before it hits the domain logic. |
| **Entities / Models** | `Ecto.Schema` | Schemas are Pure Data Objects (PODO). They DO NOT contain `save()`, `update()`, or any behavioral methods. |
| **Repository / DAO** | `Ecto.Repo` + Context | Execute all database queries explicitly through the Repo module inside Context functions. |

## 4. Coding Standards & Best Practices
- **Error Handling:** Do not use `try/catch` or raise exceptions for standard control flow. Always return `{:ok, result}` and `{:error, reason}` tuples.
- **Control Flow:** Favor **Pattern Matching** at the function signature level over `if/else`, `cond`, or `switch` statements.
  ```elixir
  # ✅ Clean Elixir Code
  def process_payment(%{status: :paid} = payment), do: complete_order(payment)
  def process_payment(payment), do: handle_error(payment)
  ```
- **Data Transformation:** Utilize the pipe operator (`|>`) to sequence functional transformations. Avoid nested function calls or attempting "method chaining".
  ```elixir
  # ✅ Ecto Query standard
  Order
  |> where([o], o.status == :paid)
  |> order_by([o], desc: o.inserted_at)
  |> Repo.all()
  ```

## 5. Standard Mix Commands
- Start server: `mix phx.server`
- Type checking: `mix dialyzer`
- Run test suite: `mix test`
- Formatting: `mix format`
