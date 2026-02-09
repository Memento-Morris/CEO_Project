# FNB BufferShield - Predictive Overdraft Simulator

A Streamlit web application demonstrating FNB's BufferShield predictive overdraft feature with realistic cost calculations, grace periods, and escalation scenarios.

## Features

✅ **Notification-based entry** - Shows upcoming debit orders and cashflow predictions
✅ **Realistic cost calculator** - Calculates interest with grace period and escalation
✅ **4-step user flow** - Amount → Period → What If → Review
✅ **Grace period handling** - 3-day grace after expected inflow
✅ **Escalation scenarios** - Shows R35 fee and higher rates when exceeding grace
✅ **FNB branding** - Dark grey, orange, and teal colors

## Local Testing

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Run the app:
```bash
streamlit run streamlit_app.py
```

3. Open browser at `http://localhost:8501`

## Deploy to Streamlit Cloud (FREE)

### Step 1: Push to GitHub

1. Create a new repository on GitHub
2. Upload these files:
   - `streamlit_app.py`
   - `requirements.txt`
   - `README.md` (this file)

### Step 2: Deploy on Streamlit Cloud

1. Go to [share.streamlit.io](https://share.streamlit.io)
2. Sign in with GitHub
3. Click "New app"
4. Select your repository
5. Set:
   - **Main file path**: `streamlit_app.py`
   - **Python version**: 3.9+
6. Click "Deploy"

Your app will be live at: `https://[your-app-name].streamlit.app`

## Usage

### Scenario Testing

**Today's date**: 9th February 2026
**Expected inflow**: 16th February 2026 (7 days)
**Grace period**: 3 days (ends 19th Feb)

**Test scenarios:**
- **3 or 7 days** - BufferShield rates (16.25% p.a.), no activation fee
- **8-10 days** - Uses grace period, still BufferShield rates
- **14 or 30 days** - Escalates to Standard OD (22.25% p.a.) + R35 activation fee

### Key Features Demonstrated

1. **Cashflow Forecasting** - Detects upcoming debit order shortfall
2. **Predictive Approval** - Pre-approves based on expected inflow
3. **Usage Limits** - "Not available if used twice in 30 days"
4. **Transparent Fees** - Shows exact costs for different scenarios
5. **Grace Period** - Automatic 3-day grace with no extra fees
6. **Escalation Path** - Clear communication about standard OD conversion

## User Flow

```
Notifications Screen
    ↓
[Click: Upcoming Debit Order Alert]
    ↓
Page 1: Select Bridging Amount
    ↓
Page 2: Select Expected Inflow Date
    ↓
Page 3: What If Things Go Wrong?
    ↓
Page 4: Review & Confirm
    ↓
Activation
```

## Cost Calculation Logic

```python
# On Time (≤ inflow + 3 days grace)
interest = amount × rate × days / 365
total = amount + interest

# Escalated (> inflow + 3 days grace)
interest = amount × standard_rate × days / 365
activation_fee = R35
total = amount + interest + activation_fee
```

## Configuration

Edit dates in `streamlit_app.py`:

```python
current_date = datetime.date(2026, 2, 9)  # Today
"inflow_date": datetime.date(2026, 2, 16)  # Expected inflow
"debit_order_date": datetime.date(2026, 2, 11)  # Debit order
```

## License

Demo/Educational Purpose
