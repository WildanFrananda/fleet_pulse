# Product Requirement Document (PRD): FleetPulse

**High-Frequency Driver Tracking & Dispatch Engine**

---

## 1. Executive Summary

FleetPulse is a specialized, real-time driver tracking and dispatch engine built specifically for last-mile logistics and niche courier fleets. Traditional dispatch systems struggle with high-frequency GPS pinging, leading to database bottlenecks and delayed routing. FleetPulse leverages the Elixir/Phoenix ecosystem to handle concurrent WebSocket connections at scale. By maintaining driver state in-memory and utilizing Phoenix LiveView, FleetPulse delivers ultra-low latency tracking and interactive dispatch dashboards directly from the server, eliminating the need for a separate frontend SPA infrastructure.

---

## 2. Problem Statement

Niche logistics providers (e.g., medical supplies, sensitive cargo, local taxi services) require precise, real-time visibility of their fleet. Existing solutions face significant challenges:

- **Database Strain:** Updating a database table every 3 seconds for 1000+ drivers quickly exhausts connection pools and I/O resources.
- **Latency in Dispatch:** Delayed location updates result in suboptimal assignments and higher customer wait times.
- **Admin Dashboard Complexity:** Building and maintaining a separate React/Vue frontend to handle real-time WebSockets for the dispatch operator adds unnecessary overhead and sync issues.
- **Connection Overhead:** Managing thousands of persistent, concurrent connections from mobile devices drains resources on traditional stateless architectures.

---

## 3. Product Vision

To provide a highly resilient, low-latency tracking and dispatch backend that acts as the "nervous system" for specialized fleet operations. It seamlessly integrates driver telemetry via mobile apps and provides a robust, real-time operational dashboard for dispatchers using Phoenix LiveView.

---

## 4. Target Market

- **Primary:** Local / Regional last-mile delivery startups (groceries, rapid commerce).
- **Secondary:** Specialized courier fleets (medical transport, sensitive/high-value cargo).
- **Tertiary:** Mid-sized regional taxi or ride-hailing operators.

---

## 5. Core Features & Requirements

### 5.1. Real-Time Telemetry Ingestion (Driver App)

- **High-Frequency Pings:** System handles GPS coordinate updates (latitude, longitude, speed, bearing, timestamp) from native mobile driver apps every 3–5 seconds.
- **Tech Enabler:** Utilize Phoenix Channels / WebSockets for persistent connections with the driver's device.

### 5.2. In-Memory Fleet State Management

- **Ephemeral Storage:** Current driver locations and availability status (online, busy, offline) are held in memory.
- **Historical Batching:** The system batches location data and persists it to the database (PostgreSQL) periodically (e.g., every 30–60 seconds) for auditing and analytics.
- **Tech Enabler:** Each active driver is represented by a GenServer process. A Registry maps the Driver ID to the corresponding process, updating state instantly without DB writes.

### 5.3. Geofencing & Spatial Queries

- **Real-Time Proximity:** Instantly query "Which drivers are within a 3km radius of coordinates X, Y?"
- **Tech Enabler:** Utilize in-memory spatial indexing (e.g., ETS tables) for immediate dispatch queries, falling back to PostGIS for complex zone boundaries.

### 5.4. LiveView Dispatch Dashboard (Admin Client)

- **Live Map View:** Dispatch operators view a real-time, moving map of all active drivers without page reloads or polling.
- **Instant Interaction:** Operators can click on a driver to assign manual orders, with changes reflecting instantly.
- **Tech Enabler:** Phoenix LiveView connects directly to the server's internal state (via Phoenix PubSub). As GenServer driver states update, LiveView pushes differential DOM updates to the dispatcher's browser automatically.

### 5.5. Intelligent Dispatch Engine

- **Algorithmic Routing:** Evaluate available drivers based on proximity and load capacity to assign incoming orders.
- **Broadcast Assignment:** Instantly push order details to the selected driver via the active WebSocket connection.

---

## 6. Architecture & Elixir Implementation Details (Clean Code Approach)

This system will strictly adhere to Phoenix Contexts, separating domain logic from web delivery.

### 6.1. System Contexts

- **`FleetPulse.Tracking` Context:** Manages telemetry ingestion, GenServer driver state processes, and geofencing.
- **`FleetPulse.Dispatch` Context:** Handles order assignment logic and evaluates driver availability.
- **`FleetPulseWeb` (Web Layer):**
  - *Endpoint & Channels:* Handles mobile app WebSocket connections.
  - *Live (LiveView Modules):* Manages the real-time Admin/Dispatcher dashboard UI.

### 6.2. Architecture Flow

1. **Mobile App (Driver)** → Sends GPS via → **Phoenix Channel**
2. **Phoenix Channel** → Updates state in → **Driver GenServer**
3. **Driver GenServer** → Broadcasts new location via → **Phoenix PubSub**
4. **Admin Dashboard (LiveView)** → Subscribed to PubSub, receives update → Pushes minimal HTML diff to the Dispatcher's browser

---

## 7. Metrics for Success

- **Latency:** End-to-end latency from driver ping to Dispatcher dashboard update under 100ms.
- **Throughput:** Sustain 10,000+ concurrent driver connections updating every 5 seconds on a single node.
- **Development Velocity:** Reduce administrative UI development time by 50% by avoiding a separate SPA architecture.

---

## 8. Out of Scope (For V1)

- Complex Turn-by-Turn Navigation (integrate with Mapbox SDK on client instead).
- Billing and Payment Processing.
- Customer-facing mobile applications (focus is on Driver App and Admin Dashboard).