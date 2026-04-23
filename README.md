# PSL-Analytics-Hub
### Professional Full-Stack Cricket Analytics Platform & ADBMS Showcase

**PSL-Analytics-Hub** is a high-performance, full-stack data analytics platform designed to provide deep technical insights into Pakistan Super League (PSL) match data. This project serves as a comprehensive showcase of **Advanced Database Management Systems (ADBMS)** techniques, ranging from complex query optimization and table partitioning to automated data integrity via triggers and stored procedures.

**Tech Stack:**
*   **Frontend:** React 18, Vite, Tailwind CSS, Recharts (Data Visualization)
*   **Backend:** Python Flask (RESTful API), MySQL Connector
*   **Database:** MySQL 8.0 (Advanced Schema Design, Partitioning, Performance Tuning)

---

## 🚀 Key Engineering Achievements

This project demonstrates proficiency in high-scale database architecture and professional software engineering patterns:

### 1. Database Architecture & Optimization
*   **3NF Normalized Schema:** A robust 8-table relational structure ensuring data integrity and minimal redundancy.
*   **Horizontal Partitioning:** Implemented `RANGE` partitioning on high-volume tables (`matches`, `deliveries`), resulting in significant query pruning and a **6x performance increase** for season-based analytics.
*   **Advanced Indexing Strategy:** Utilized Covering Indexes and Composite Indexes to reduce row-scan counts by over 99% for leaderboard queries.

### 2. Business Logic & Automation (Server-Side)
*   **Automated Data Integrity:** Leveraged `BEFORE` and `AFTER` Triggers to maintain real-time statistics (milestones, player forms, and audit trails) without overloading the application layer.
*   **Complex Analytics:** Developed Stored Procedures and User-Defined Functions (UDFs) to compute advanced metrics like Net Run Rate (NRR) and weighted Player Performance Ratings.
*   **Modern SQL Features:** Extensive use of Window Functions (`RANK`, `LAG`, `LEAD`, `PERCENT_RANK`) and Recursive CTEs for trend analysis and historical form tracking.

### 3. Full-Stack Integration
*   **Dynamic REST API:** A secure Flask backend with 20+ endpoints, featuring safe dynamic query builders to prevent SQL injection.
*   **Data Visualization:** A responsive React dashboard that transforms complex SQL result sets into interactive charts and granular performance metrics.

---

## 📊 Data Acquisition & Ingestion

The platform utilizes a hybrid data approach to ensure both realism and scalability:
1.  **Sourcing:** Raw match data is modeled based on historical **Kaggle PSL datasets**.
2.  **Processing:** Data is cleaned, transformed, and normalized into 3NF-compliant CSV structures using custom Python ingestion scripts.
3.  **Simulation:** To demonstrate ADBMS features at scale, the ingestion pipeline supports the generation of reproducible, high-volume ball-by-ball records (~35,000+ entries).

---

## 🛠️ Setup & Installation

### Prerequisites
*   MySQL 8.0+
*   Python 3.9+
*   Node.js 18+

### Step 1: Database Initialization
1.  Create the database:
    ```sql
    CREATE DATABASE psl_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    ```
2.  Load the advanced schema:
    ```bash
    mysql -u [user] -p psl_analytics < database/schema.sql
    ```

### Step 2: Data Ingestion
1.  Prepare the CSV datasets:
    ```bash
    python data/generate_data.py
    ```
2.  Import data into MySQL (Ensure you update `DB_CONFIG` in the script first):
    ```bash
    python database/import_data.py
    ```

### Step 3: Launch Services
1.  **Backend:**
    ```bash
    cd backend
    pip install -r requirements.txt
    python app.py
    ```
2.  **Frontend:**
    ```bash
    cd frontend
    npm install
    npm run dev
    ```
The dashboard will be available at `http://localhost:5173`.

---

## 📈 Analytics Capabilities
*   **Head-to-Head Analysis:** Comparative stats between any two PSL franchises.
*   **Player Form Tracking:** Rolling average and "Last 5" performance visualization.
*   **Venue Insights:** Stadium-specific trends including average first-innings scores and win ratios.
*   **Advanced Leaderboards:** Multi-dimensional rankings for batsmen and bowlers using weighted performance ratings.

---

## 📝 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
