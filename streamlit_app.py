import streamlit as st
import datetime

# Page config
st.set_page_config(
    page_title="FNB BufferShield",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# Custom CSS for FNB branding - light grey theme with teal accents
st.markdown("""
<style>
    /* FNB Actual Colors - subdued palette */
    :root {
        --fnb-teal: #00A9CE;        /* Primary accent - teal */
        --fnb-orange: #FF9900;      /* Secondary accent - use sparingly */
        --fnb-dark: #333333;        /* Dark text */
        --fnb-grey: #666666;        /* Medium grey */
        --fnb-light-grey: #F5F5F5;  /* Light backgrounds */
        --fnb-lighter-grey: #FAFAFA; /* Even lighter */
        --fnb-border: #E0E0E0;      /* Borders */
        --fnb-white: #FFFFFF;
        --fnb-green: #00A651;       /* Success green */
        --fnb-red: #E31E24;         /* Error red */
    }
    
    /* Hide Streamlit branding */
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
    header {visibility: hidden;}
    
    /* Overall page styling - light grey background */
    .stApp {
        background-color: #FAFAFA;
    }
    
    /* Custom FNB header - subdued grey */
    .fnb-header {
        background: #F5F5F5;
        padding: 25px 20px;
        margin: -1rem -1rem 2rem -1rem;
        border-bottom: 1px solid #E0E0E0;
    }
    
    .fnb-header h1 {
        color: #333333;
        margin: 0;
        font-size: 24px;
        font-weight: 600;
    }
    
    .fnb-header p {
        color: #666666;
        margin: 5px 0 0 0;
        font-size: 14px;
    }
    
    /* White card styling with rounded edges and shadow */
    .fnb-card {
        background: white;
        padding: 20px;
        border-radius: 12px;
        border: 1px solid #E0E0E0;
        margin: 15px 0;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
    }
    
    .notification-card {
        background: white;
        padding: 18px;
        border-radius: 12px;
        border: 1px solid #E0E0E0;
        margin: 12px 0;
        cursor: pointer;
        transition: all 0.2s ease;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
    }
    
    .notification-card:hover {
        border-color: #00A9CE;
        box-shadow: 0 4px 12px rgba(0, 169, 206, 0.15);
    }
    
    /* Section headers - OUTSIDE cards */
    .section-header {
        color: #00A9CE;
        font-size: 18px;
        font-weight: 600;
        margin: 25px 0 15px 0;
    }
    
    /* Teal subheadings */
    .teal-heading {
        color: #00A9CE;
        font-size: 16px;
        font-weight: 600;
        margin: 20px 0 10px 0;
    }
    
    /* Text colors */
    .teal-text {
        color: #00A9CE;
        font-weight: 600;
    }
    
    .orange-text {
        color: #FF9900;
        font-weight: 600;
    }
    
    .green-text {
        color: #00A651;
        font-weight: 600;
    }
    
    .red-text {
        color: #E31E24;
        font-weight: 600;
    }
    
    .grey-text {
        color: #666666;
        font-size: 14px;
    }
    
    .dark-text {
        color: #333333;
        font-weight: 600;
    }
    
    /* Progress dots */
    .progress-dots {
        display: flex;
        justify-content: center;
        align-items: center;
        margin: 20px 0;
        gap: 10px;
    }
    
    .dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #E0E0E0;
    }
    
    .dot.active {
        background: #00A9CE;
        width: 10px;
        height: 10px;
    }
    
    .dot.completed {
        background: #00A9CE;
        opacity: 0.5;
    }
    
    .dot-line {
        width: 30px;
        height: 2px;
        background: #E0E0E0;
    }
    
    .dot-line.completed {
        background: #00A9CE;
        opacity: 0.5;
    }
    
    /* Buttons - light gray with black text and rounded edges */
    .stButton > button {
        width: 100%;
        background: #F5F5F5;
        color: #333333;
        border: 1px solid #E0E0E0;
        padding: 14px 24px;
        font-size: 15px;
        font-weight: 600;
        border-radius: 12px;
        cursor: pointer;
        transition: all 0.2s ease;
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
    }
    
    .stButton > button:hover {
        background: #EEEEEE;
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.12);
        border-color: #D0D0D0;
    }
    
    .stButton > button:active {
        background: #E8E8E8;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
    }
    
    /* Primary button - teal */
    .stButton > button[kind="primary"],
    .stButton > button.primary-button {
        background: #00A9CE;
        color: white;
        border: none;
    }
    
    .stButton > button[kind="primary"]:hover,
    .stButton > button.primary-button:hover {
        background: #0096B8;
    }
    
    .stButton > button[kind="primary"]:active,
    .stButton > button.primary-button:active {
        background: #008CAD;
    }
    
    /* Full width button container */
    div[data-testid="column"] > div > div > div > button {
        width: 100%;
    }
    
    /* Amount display */
    .amount-display {
        text-align: center;
        font-size: 48px;
        font-weight: 700;
        color: #333333;
        margin: 25px 0;
    }
    
    .amount-display .currency {
        font-size: 24px;
        color: #666666;
        margin-right: 5px;
    }
    
    /* Warning card */
    .warning-card {
        background: #FFF5F5;
        padding: 18px;
        border-radius: 12px;
        border-left: 3px solid #E31E24;
        margin: 15px 0;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
    }
    
    /* Info card */
    .info-card {
        background: #F0FAFF;
        padding: 18px;
        border-radius: 12px;
        border-left: 3px solid #00A9CE;
        margin: 15px 0;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
    }
    
    /* Success card */
    .success-card {
        background: #F0FFF4;
        padding: 18px;
        border-radius: 12px;
        border-left: 3px solid #00A651;
        margin: 15px 0;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
    }
    
    /* Slider */
    .stSlider > div > div > div {
        background: #00A9CE;
    }
    
    /* Compact text */
    .compact {
        font-size: 13px;
        color: #666666;
        line-height: 1.5;
    }
    
    /* Table styling */
    .cost-table {
        width: 100%;
        margin: 10px 0;
    }
    
    .cost-row {
        display: flex;
        justify-content: space-between;
        padding: 12px 0;
        border-bottom: 1px solid #F5F5F5;
    }
    
    .cost-row:last-child {
        border-bottom: none;
        border-top: 2px solid #E0E0E0;
        margin-top: 10px;
        padding-top: 15px;
        font-weight: 600;
    }
    
    /* Hide default streamlit elements */
    div[data-testid="stDecoration"] {
        display: none;
    }
</style>
""", unsafe_allow_html=True)

# Initialize session state
if 'page' not in st.session_state:
    st.session_state.page = 0
if 'selected_amount' not in st.session_state:
    st.session_state.selected_amount = 1250
if 'selected_days' not in st.session_state:
    st.session_state.selected_days = 7

# User data
user_data = {
    "name": "John Doe",
    "account_number": "****7823",
    "current_balance": 450.00,
    "inflow_date": datetime.date(2026, 2, 16),
    "predicted_inflow": 18500,
    "buffer_limit": 2000,
    "buffer_available": 2000,
    "activations_used": 1,
    "activations_limit": 2,
    "interest_rate": 16.25,
    "standard_rate": 22.25,
    "grace_days": 3,
    "activation_fee_standard": 35,
    "debit_order_amount": 1250.00,
    "debit_order_date": datetime.date(2026, 2, 11),
    "debit_order_recipient": "DStv",
    "flagged_reason": "Upcoming debit order",
    "predicted_shortfall": 800.00
}

current_date = datetime.date(2026, 2, 9)

# Helper functions
def calculate_interest(amount, days, rate):
    """Calculate simple interest"""
    return amount * (rate / 100) * (days / 365)

def calculate_full_cost(amount, expected_days):
    """Calculate full cost including grace period and escalation"""
    inflow_days = (user_data['inflow_date'] - current_date).days
    
    if expected_days <= inflow_days + user_data['grace_days']:
        # On time or within grace
        interest = calculate_interest(amount, expected_days, user_data['interest_rate'])
        return {
            'scenario': 'on_time',
            'interest': interest,
            'activation_fee': 0,
            'total': amount + interest,
            'rate': user_data['interest_rate'],
            'days_at_buffer_rate': expected_days,
            'days_at_standard_rate': 0,
            'grace_used': max(0, expected_days - inflow_days)
        }
    else:
        # Escalated
        interest = calculate_interest(amount, expected_days, user_data['standard_rate'])
        activation_fee = user_data['activation_fee_standard']
        grace_end = inflow_days + user_data['grace_days']
        days_beyond_grace = expected_days - grace_end
        
        return {
            'scenario': 'escalated',
            'interest': interest,
            'activation_fee': activation_fee,
            'total': amount + interest + activation_fee,
            'rate': user_data['standard_rate'],
            'days_at_buffer_rate': 0,
            'days_at_standard_rate': expected_days,
            'grace_used': user_data['grace_days'],
            'days_beyond_grace': days_beyond_grace,
            'escalation_date': current_date + datetime.timedelta(days=grace_end)
        }

def show_progress_dots(current_step, total_steps=4):
    """Display progress dots - FNB website style"""
    dots_html = '<div class="progress-dots">'
    for i in range(1, total_steps + 1):
        if i < current_step:
            dots_html += '<div class="dot completed"></div>'
        elif i == current_step:
            dots_html += '<div class="dot active"></div>'
        else:
            dots_html += '<div class="dot"></div>'
        
        if i < total_steps:
            line_class = 'completed' if i < current_step else ''
            dots_html += f'<div class="dot-line {line_class}"></div>'
    
    dots_html += '</div>'
    st.markdown(dots_html, unsafe_allow_html=True)

# Page 0: Notification Screen
def show_notification_screen():
    st.markdown("""
    <div class="fnb-header">
        <h1>Notifications</h1>
        <p>Important updates for you</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Today</p>', unsafe_allow_html=True)
    
    # Notification 1: Action Required
    st.markdown("""
    <div class="notification-card" style="border-left: 3px solid #E31E24;">
        <div style="display: flex; justify-content: space-between; align-items: start;">
            <div style="flex: 1;">
                <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">Action Required: Upcoming Debit Order</p>
                <p class="grey-text" style="margin: 5px 0 0 0;">{} • R{:,.2f} on {}</p>
                <p class="compact" style="margin: 5px 0 0 0;">Predicted shortfall detected. BufferShield available.</p>
            </div>
            <span style="color: #00A9CE; font-size: 18px;">→</span>
        </div>
    </div>
    """.format(
        user_data['debit_order_recipient'],
        user_data['debit_order_amount'],
        user_data['debit_order_date'].strftime('%d %b')
    ), unsafe_allow_html=True)
    
    if st.button("View BufferShield Offer", key="notif1_btn", use_container_width=True):
        st.session_state.page = 1
        st.rerun()
    
    # Notification 2: Suggestion
    st.markdown("""
    <div class="notification-card" style="margin-top: 15px;">
        <div style="display: flex; justify-content: space-between; align-items: start;">
            <div style="flex: 1;">
                <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">Suggested: Reschedule Debit Order</p>
                <p class="grey-text" style="margin: 5px 0 0 0;">{} debit order</p>
                <p class="compact" style="margin: 5px 0 0 0;">Move to after your next inflow for better cashflow</p>
            </div>
        </div>
    </div>
    """.format(user_data['debit_order_recipient']), unsafe_allow_html=True)
    
    st.markdown('<p class="section-header" style="margin-top: 30px;">Yesterday</p>', unsafe_allow_html=True)
    
    # Notification 3: Insight
    st.markdown("""
    <div class="notification-card">
        <div style="display: flex; justify-content: space-between; align-items: start;">
            <div style="flex: 1;">
                <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">Cashflow Insight</p>
                <p class="grey-text" style="margin: 5px 0 0 0;">Your spending pattern detected</p>
                <p class="compact" style="margin: 5px 0 0 0;">R2,450 spent on groceries this month vs R2,100 last month</p>
            </div>
        </div>
    </div>
    """, unsafe_allow_html=True)

# Page 1: Amount Selection
def show_page_1():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(1, 4)
    
    # Usage limit
    st.markdown(f"""
    <div class="fnb-card" style="background: #F5F5F5;">
        <p class="compact" style="margin: 0;">Not available if used twice in 30 days • Currently: {user_data['activations_used']}/2</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Why you qualify
    st.markdown('<p class="section-header">Why you qualify</p>', unsafe_allow_html=True)
    
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0 0 5px 0;">{user_data['flagged_reason']}: {user_data['debit_order_recipient']} R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}</p>
        <p class="red-text compact" style="margin: 0;">Predicted shortfall: R{user_data['predicted_shortfall']:,.2f}</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Bridging amount needed?</p>', unsafe_allow_html=True)
    
    # Amount display
    st.markdown(f'<div class="amount-display"><span class="currency">R</span>{st.session_state.selected_amount:,}</div>', unsafe_allow_html=True)
    
    # Slider
    st.session_state.selected_amount = st.slider(
        "Select amount",
        min_value=100,
        max_value=user_data['buffer_limit'],
        value=st.session_state.selected_amount,
        step=50,
        label_visibility="collapsed"
    )
    
    # Quick select buttons
    st.markdown("**Quick select:**")
    cols = st.columns(4)
    amounts = [int(user_data['debit_order_amount']), 1000, 1500, 2000]
    labels = ["Debit order", "R1,000", "R1,500", "R2,000"]
    
    for i, (col, amount, label) in enumerate(zip(cols, amounts, labels)):
        with col:
            if st.button(f"R{amount}\n{label if i == 0 else ''}", key=f"quick_{amount}", use_container_width=True):
                st.session_state.selected_amount = amount
                st.rerun()
    
    # Next inflow info - FNB card style
    st.markdown(f"""
    <div class="fnb-card" style="text-align: center; background: #F0FFF4;">
        <p class="grey-text" style="margin: 0 0 5px 0;">Next expected inflow</p>
        <p class="green-text" style="margin: 0; font-size: 22px;">R{user_data['predicted_inflow']:,}</p>
        <p class="compact" style="margin: 5px 0 0 0;">{user_data['inflow_date'].strftime('%d %B %Y')}</p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Continue", key="continue1", use_container_width=True):
        st.session_state.page = 2
        st.rerun()
    
    if st.button("← Back", key="back1"):
        st.session_state.page = 0
        st.rerun()

# Page 2: Expected Inflow Date
def show_page_2():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(2, 4)
    
    st.markdown("### Expected inflow date?")
    st.markdown(f"**Bridging amount:** R{st.session_state.selected_amount:,}")
    st.markdown('<p class="grey-text">When do you expect to receive money? (affects interest)</p>', unsafe_allow_html=True)
    
    # Period selection
    periods = [
        (3, "3 Days", "Lowest interest"),
        (7, "7 Days", "Recommended"),
        (14, "14 Days", "Two weeks"),
        (30, "30 Days", "Maximum")
    ]
    
    for days, label, sublabel in periods:
        if st.button(f"**{label}** • {sublabel}", key=f"period_{days}", use_container_width=True):
            st.session_state.selected_days = days
            st.rerun()
    
    # Show current selection and cost
    cost_details = calculate_full_cost(st.session_state.selected_amount, st.session_state.selected_days)
    inflow_days = (user_data['inflow_date'] - current_date).days
    grace_end_days = inflow_days + user_data['grace_days']
    
    st.markdown("---")
    
    st.markdown('<p class="section-header">Cost for selected period</p>', unsafe_allow_html=True)
    
    if cost_details['scenario'] == 'on_time':
        st.markdown(f"""
        <div class="fnb-card">
            <div class="cost-table">
                <div class="cost-row" style="border: none;">
                    <span class="grey-text">{st.session_state.selected_days} days:</span>
                    <span class="teal-text">R{cost_details['interest']:.2f}</span>
                </div>
                <div class="cost-row">
                    <span style="font-weight: 600; color: #333333;">Total to repay:</span>
                    <span style="font-weight: 600; color: #333333;">R{cost_details['total']:.2f}</span>
                </div>
            </div>
            {f'<p class="compact" style="margin: 10px 0 0 0; color: #00A651;">Using {cost_details["grace_used"]} grace day(s)</p>' if cost_details['grace_used'] > 0 else ''}
        </div>
        """, unsafe_allow_html=True)
    else:
        st.markdown(f"""
        <div class="warning-card">
            <p class="red-text" style="margin: 0 0 10px 0;">Escalation Scenario</p>
            <p class="grey-text" style="margin: 0 0 10px 0;">Your expected inflow is on {user_data['inflow_date'].strftime('%d %b')} (day {inflow_days}).<br>
            Grace period ends day {grace_end_days} ({(current_date + datetime.timedelta(days=grace_end_days)).strftime('%d %b')}).</p>
            <p style="font-weight: 600; margin: 10px 0; color: #333333;">Since {st.session_state.selected_days} days exceeds grace period:</p>
            <div class="cost-table">
                <div class="cost-row" style="border: none;">
                    <span class="grey-text">Interest (Standard OD):</span>
                    <span class="red-text">R{cost_details['interest']:.2f}</span>
                </div>
                <div class="cost-row" style="border: none;">
                    <span class="grey-text">Activation fee:</span>
                    <span class="red-text">R{cost_details['activation_fee']:.2f}</span>
                </div>
                <div class="cost-row">
                    <span style="font-weight: 600; color: #333333;">Total cost:</span>
                    <span style="font-weight: 600; color: #E31E24;">R{cost_details['total']:.2f}</span>
                </div>
            </div>
            <p class="red-text compact" style="margin: 10px 0 0 0;">At {cost_details['rate']:.2f}% p.a. (Standard overdraft)</p>
        </div>
        """, unsafe_allow_html=True)
    
    # Comparison scenarios - NOW IN A CARD
    st.markdown('<p class="section-header">Compare scenarios</p>', unsafe_allow_html=True)
    
    comparison_html = '<div class="fnb-card"><div class="cost-table">'
    
    for days in [3, 7, 14, 30]:
        scenario = calculate_full_cost(st.session_state.selected_amount, days)
        is_selected = days == st.session_state.selected_days
        is_escalated = scenario['scenario'] == 'escalated'
        
        label = f"→ {days} days" if is_selected else f"{days} days"
        if is_escalated:
            label += " (Escalated)"
        
        if is_escalated:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #666666; {"font-weight: 600;" if is_selected else ""}">{label}</span><span style="color: #E31E24; font-weight: 600;">R{scenario["total"]:.2f}</span></div>'
        elif is_selected:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #333333; font-weight: 600;">{label}</span><span style="color: #00A9CE; font-weight: 600;">R{scenario["total"]:.2f}</span></div>'
        else:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #666666;">{label}</span><span style="color: #666666;">R{scenario["total"]:.2f}</span></div>'
    
    comparison_html += '</div><p class="compact" style="margin: 10px 0 0 0;">Escalated = Standard overdraft with activation fee</p></div>'
    st.markdown(comparison_html, unsafe_allow_html=True)
    
    # Predicted inflow
    days_until = (user_data['inflow_date'] - current_date).days
    st.markdown(f"""
    <div class="info-card">
        <p class="teal-text" style="margin: 0 0 5px 0; font-size: 15px;">Next predicted inflow: {user_data['inflow_date'].strftime('%d %B')}</p>
        <p class="grey-text" style="margin: 0;">in {days_until} days • We'll auto-repay from this</p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Continue", key="continue2", use_container_width=True):
        st.session_state.page = 3
        st.rerun()
    
    if st.button("← Back", key="back2"):
        st.session_state.page = 1
        st.rerun()

# Page 3: What if things go wrong?
def show_page_3():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(3, 4)
    
    st.markdown('<p class="section-header">What if things go wrong?</p>', unsafe_allow_html=True)
    st.markdown('<p class="grey-text">We\'ve got you covered with transparent processes</p>', unsafe_allow_html=True)
    
    # Grace Period
    st.markdown('<p class="teal-heading">Grace Period</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">If your predicted inflow doesn't arrive on time, you get an automatic 3-day grace period with no additional fees. We understand that salary dates can shift.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Escalation
    st.markdown('<p class="teal-heading">Escalation to Standard Overdraft</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">After the grace period, if still unpaid, BufferShield converts to a standard overdraft facility at {user_data['standard_rate']}% p.a. No surprise fees—you'll know exactly what changes.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Communication
    st.markdown('<p class="teal-heading">Proactive Communication</p>', unsafe_allow_html=True)
    st.markdown("""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">We'll notify you:<br>
        • 2 days before expected repayment<br>
        • On repayment day<br>
        • If grace period activates<br>
        • Before any rate changes<br><br>
        You're always in control via the FNB App.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Fee Transparency - info card style
    st.markdown('<p class="teal-heading">Fee Transparency</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="info-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">
        Current BufferShield rate: {user_data['interest_rate']}% p.a.<br>
        Standard overdraft rate: {user_data['standard_rate']}% p.a.<br>
        Activation fee: R0.00<br>
        Monthly fee: R0.00<br><br>
        <strong style="color: #333333;">No hidden costs. Ever.</strong></p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Review & Confirm", key="continue3", use_container_width=True):
        st.session_state.page = 4
        st.rerun()
    
    if st.button("← Back", key="back3"):
        st.session_state.page = 2
        st.rerun()

# Page 4: Review & Confirm
def show_page_4():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(4, 4)
    
    st.markdown('<p class="section-header">Review Details</p>', unsafe_allow_html=True)
    
    # Summary card - teal theme
    st.markdown(f"""
    <div class="fnb-card" style="background: #F5F5F5; text-align: center; padding: 30px 20px; border-left: 3px solid #00A9CE;">
        <p style="color: #666666; margin: 0 0 10px 0; font-size: 14px;">Bridging amount</p>
        <h1 style="color: #333333; margin: 10px 0 20px 0; font-size: 42px; font-weight: 700;">R{st.session_state.selected_amount:,}</h1>
        <div style="height: 2px; background: #00A9CE; margin: 20px auto; width: 80px;"></div>
        <p style="color: #666666; margin: 10px 0 0 0; font-size: 15px;">Expected repay: <strong style="color: #333333;">{st.session_state.selected_days} days</strong></p>
    </div>
    """, unsafe_allow_html=True)
    
    # Cost breakdown
    st.markdown('<p class="section-header">Total cost breakdown</p>', unsafe_allow_html=True)
    
    cost_details = calculate_full_cost(st.session_state.selected_amount, st.session_state.selected_days)
    
    # Build the cost breakdown in HTML
    cost_html = '<div class="fnb-card"><div class="cost-table">'
    
    if cost_details['scenario'] == 'on_time':
        items = [
            ("Bridging amount", f"R{st.session_state.selected_amount:,.2f}", False),
            ("Interest charge", f"R{cost_details['interest']:.2f}", False),
            ("Rate", f"{cost_details['rate']:.2f}% p.a. (BufferShield)", False),
            ("Activation fee", "R0.00", False),
            ("Monthly fee", "R0.00", False)
        ]
        if cost_details['grace_used'] > 0:
            items.insert(3, ("Grace period used", f"{cost_details['grace_used']} day(s)", False))
    else:
        items = [
            ("Bridging amount", f"R{st.session_state.selected_amount:,.2f}", False),
            ("Interest charge", f"R{cost_details['interest']:.2f}", True),
            ("Rate", f"{cost_details['rate']:.2f}% p.a. (Standard OD)", True),
            ("Activation fee", f"R{cost_details['activation_fee']:.2f}", True),
            ("Grace period exceeded", f"by {cost_details['days_beyond_grace']} day(s)", True)
        ]
    
    # Add each row
    for i, (label, value, is_warning) in enumerate(items):
        color = "#E31E24" if is_warning else "#666666"
        value_color = "#E31E24" if is_warning else "#333333"
        border = 'border-bottom: 1px solid #F0F0F0;' if i < len(items) else ''
        cost_html += f'<div class="cost-row" style="{border}"><span style="color: {color};">{label}</span><span style="font-weight: 600; color: {value_color};">{value}</span></div>'
    
    # Add total row
    total_color = "#E31E24" if cost_details['scenario'] == 'escalated' else "#333333"
    cost_html += f'<div class="cost-row" style="border-top: 2px solid #333333; border-bottom: none; margin-top: 10px; padding-top: 12px;"><span style="font-weight: 600; color: #333333;">Total repayment</span><span style="font-weight: 700; color: {total_color}; font-size: 18px;">R{cost_details["total"]:.2f}</span></div>'
    
    cost_html += '</div>'  # Close cost-table
    
    # Escalation warning if applicable
    if cost_details['scenario'] == 'escalated':
        cost_html += f'<p class="red-text compact" style="margin: 12px 0 0 0;">⚠️ Escalates to standard overdraft on {cost_details["escalation_date"].strftime("%d %b")}</p>'
    
    cost_html += '</div>'  # Close fnb-card
    
    st.markdown(cost_html, unsafe_allow_html=True)
    
    # Auto-repay
    st.markdown(f"""
    <div class="info-card">
        <p class="teal-text" style="margin: 0 0 8px 0; font-size: 15px;">Auto-Repay</p>
        <p class="grey-text" style="margin: 0 0 3px 0;">Date: {user_data['inflow_date'].strftime('%d %B %Y')}</p>
        <p class="grey-text" style="margin: 0;">Amount: R{cost_details['total']:.2f} from predicted inflow</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Terms
    st.markdown('<p class="compact" style="text-align: center;">By activating, you agree to BufferShield terms.<br>Funds available immediately after confirmation.</p>', unsafe_allow_html=True)
    
    # Action buttons
    col1, col2 = st.columns(2)
    
    with col1:
        if st.button("✓ Activate BufferShield", key="activate", type="primary", use_container_width=True):
            if user_data['activations_used'] >= user_data['activations_limit']:
                st.error(f"❌ Usage Limit\n\nNot available if used twice in 30 days.\n\nCurrent usage: {user_data['activations_used']}/{user_data['activations_limit']}")
            else:
                st.success(f"""
                ✅ **BufferShield Activated!**
                
                New balance: R{user_data['current_balance'] + st.session_state.selected_amount:,.2f}
                
                Repayment: {user_data['inflow_date'].strftime('%d %B')}
                
                Amount: R{cost_details['total']:.2f}
                
                Usage: {user_data['activations_used'] + 1}/{user_data['activations_limit']} this month
                
                {f"⚠️ Will escalate to standard OD on {cost_details['escalation_date'].strftime('%d %B')}" if cost_details['scenario'] == 'escalated' else ''}
                """)
    
    with col2:
        if st.button("Decline Offer", key="decline", use_container_width=True):
            st.info("Offer declined. You can access BufferShield anytime from Notifications.")
            st.session_state.page = 0
            st.rerun()
    
    if st.button("← Back", key="back4"):
        st.session_state.page = 3
        st.rerun()

# Main app routing
if st.session_state.page == 0:
    show_notification_screen()
elif st.session_state.page == 1:
    show_page_1()
elif st.session_state.page == 2:
    show_page_2()
elif st.session_state.page == 3:
    show_page_3()
elif st.session_state.page == 4:
    show_page_4()
