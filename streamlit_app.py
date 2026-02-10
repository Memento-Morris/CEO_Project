import streamlit as st
import datetime

# Page config
st.set_page_config(
    page_title="FNB BufferShield",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# Custom CSS for FNB branding matching actual website
st.markdown("""
<style>
    /* FNB Actual Colors from website */
    :root {
        --fnb-gold: #FF9900;        /* Primary FNB Orange/Gold */
        --fnb-dark: #333333;        /* Dark text */
        --fnb-grey: #666666;        /* Medium grey */
        --fnb-light-grey: #F5F5F5;  /* Light backgrounds */
        --fnb-border: #DDDDDD;      /* Borders */
        --fnb-white: #FFFFFF;
        --fnb-green: #00A651;       /* Success green */
        --fnb-red: #E31E24;         /* Error red */
    }
    
    /* Hide Streamlit branding */
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
    header {visibility: hidden;}
    
    /* Overall page styling */
    .stApp {
        background-color: #F5F5F5;
    }
    
    /* Custom FNB header */
    .fnb-header {
        background: linear-gradient(to right, #FF9900 0%, #FF9900 100%);
        padding: 25px 20px;
        margin: -1rem -1rem 2rem -1rem;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    
    .fnb-header h1 {
        color: white;
        margin: 0;
        font-size: 22px;
        font-weight: 600;
        letter-spacing: 0.5px;
    }
    
    .fnb-header p {
        color: white;
        margin: 5px 0 0 0;
        font-size: 13px;
        opacity: 0.95;
    }
    
    /* White card styling - matching FNB website */
    .fnb-card {
        background: white;
        padding: 20px;
        border-radius: 4px;
        border: 1px solid #DDDDDD;
        margin: 15px 0;
        box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    }
    
    .notification-card {
        background: white;
        padding: 18px;
        border-radius: 4px;
        border: 1px solid #DDDDDD;
        margin: 12px 0;
        cursor: pointer;
        transition: all 0.2s ease;
        box-shadow: 0 1px 2px rgba(0,0,0,0.05);
    }
    
    .notification-card:hover {
        border-color: #FF9900;
        box-shadow: 0 2px 6px rgba(255,153,0,0.15);
        transform: translateY(-1px);
    }
    
    /* Section headers */
    .section-header {
        color: #333333;
        font-size: 18px;
        font-weight: 600;
        margin: 25px 0 15px 0;
        padding-bottom: 8px;
        border-bottom: 2px solid #FF9900;
    }
    
    /* Text colors matching FNB */
    .gold-text {
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
    
    /* Progress dots - FNB style */
    .progress-dots {
        display: flex;
        justify-content: center;
        align-items: center;
        margin: 20px 0;
        gap: 10px;
    }
    
    .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: #DDDDDD;
    }
    
    .dot.active {
        background: #FF9900;
        width: 12px;
        height: 12px;
    }
    
    .dot.completed {
        background: #FF9900;
        opacity: 0.6;
    }
    
    .dot-line {
        width: 30px;
        height: 2px;
        background: #DDDDDD;
    }
    
    .dot-line.completed {
        background: #FF9900;
        opacity: 0.6;
    }
    
    /* Buttons - FNB style */
    .stButton > button {
        width: 100%;
        background: linear-gradient(to bottom, #FF9900 0%, #FF8800 100%);
        color: white;
        border: none;
        padding: 14px 24px;
        font-size: 15px;
        font-weight: 600;
        border-radius: 4px;
        cursor: pointer;
        transition: all 0.2s ease;
        text-transform: none;
        letter-spacing: 0.3px;
    }
    
    .stButton > button:hover {
        background: linear-gradient(to bottom, #FF8800 0%, #FF7700 100%);
        box-shadow: 0 2px 8px rgba(255,153,0,0.3);
        transform: translateY(-1px);
    }
    
    /* Secondary buttons */
    div[data-testid="column"] .stButton > button {
        background: white;
        color: #FF9900;
        border: 2px solid #FF9900;
    }
    
    div[data-testid="column"] .stButton > button:hover {
        background: #FFF5E6;
        border-color: #FF8800;
    }
    
    /* Amount display - large and prominent */
    .amount-display {
        text-align: center;
        font-size: 52px;
        font-weight: 700;
        color: #333333;
        margin: 25px 0;
        letter-spacing: -1px;
    }
    
    .amount-display .currency {
        font-size: 28px;
        color: #666666;
        margin-right: 5px;
    }
    
    /* Warning card - FNB style */
    .warning-card {
        background: #FFF5F5;
        padding: 18px;
        border-radius: 4px;
        border-left: 4px solid #E31E24;
        margin: 15px 0;
    }
    
    /* Info card - FNB style */
    .info-card {
        background: #F0F8FF;
        padding: 18px;
        border-radius: 4px;
        border-left: 4px solid #0066CC;
        margin: 15px 0;
    }
    
    /* Success card */
    .success-card {
        background: #F0FFF4;
        padding: 18px;
        border-radius: 4px;
        border-left: 4px solid #00A651;
        margin: 15px 0;
    }
    
    /* Slider customization */
    .stSlider > div > div > div {
        background: #FF9900;
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
        margin: 15px 0;
    }
    
    .cost-row {
        display: flex;
        justify-content: space-between;
        padding: 10px 0;
        border-bottom: 1px solid #F0F0F0;
    }
    
    .cost-row:last-child {
        border-bottom: none;
        border-top: 2px solid #333333;
        margin-top: 10px;
        padding-top: 12px;
        font-weight: 600;
    }
    
    /* Icon styling */
    .icon {
        font-size: 24px;
        margin-right: 12px;
    }
    
    /* Divider */
    .fnb-divider {
        height: 2px;
        background: #FF9900;
        margin: 20px 0;
        width: 60px;
    }
    
    /* Hide default streamlit elements */
    div[data-testid="stDecoration"] {
        display: none;
    }
    
    /* Custom scrollbar */
    ::-webkit-scrollbar {
        width: 8px;
    }
    
    ::-webkit-scrollbar-track {
        background: #F5F5F5;
    }
    
    ::-webkit-scrollbar-thumb {
        background: #DDDDDD;
        border-radius: 4px;
    }
    
    ::-webkit-scrollbar-thumb:hover {
        background: #CCCCCC;
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
    
    # Notification 1: Action Required (styled as FNB notification)
    st.markdown("""
    <div class="notification-card" style="border-left: 4px solid #E31E24;">
        <div style="display: flex; align-items: start;">
            <span class="icon" style="color: #E31E24;">⚠️</span>
            <div style="flex: 1;">
                <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">Action Required: Upcoming Debit Order</p>
                <p class="grey-text" style="margin: 5px 0 0 0;">{} • R{:,.2f} on {}</p>
                <p class="compact" style="margin: 5px 0 0 0;">Predicted shortfall detected. BufferShield available.</p>
            </div>
            <span style="color: #FF9900; font-size: 20px;">→</span>
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
        <div style="display: flex; align-items: start;">
            <span class="icon" style="color: #FF9900;">📅</span>
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
        <div style="display: flex; align-items: start;">
            <span class="icon" style="color: #00A651;">📊</span>
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
    
    # Usage limit - FNB style
    st.markdown(f"""
    <div class="fnb-card" style="background: #FFF5E6; border-left: 3px solid #FF9900;">
        <p class="compact" style="margin: 0;">⚡ Not available if used twice in 30 days • Currently: {user_data['activations_used']}/2</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Why you qualify - FNB style
    st.markdown(f"""
    <div class="fnb-card">
        <p class="gold-text" style="margin: 0 0 8px 0; font-size: 15px;">🔮 Why you qualify</p>
        <p class="grey-text" style="margin: 0 0 5px 0;">{user_data['flagged_reason']}: {user_data['debit_order_recipient']} R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}</p>
        <p class="red-text compact" style="margin: 0;">Predicted shortfall: R{user_data['predicted_shortfall']:,.2f}</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Bridging amount needed?</p>', unsafe_allow_html=True)
    
    # Amount display - large and centered
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
    
    if cost_details['scenario'] == 'on_time':
        st.markdown(f"""
        <div class="fnb-card">
            <p style="font-weight: 600; color: #333333; margin: 0 0 12px 0;">💰 Cost for selected period</p>
            <div class="cost-table">
                <div class="cost-row" style="border: none;">
                    <span class="grey-text">{st.session_state.selected_days} days:</span>
                    <span class="gold-text">R{cost_details['interest']:.2f}</span>
                </div>
                <div class="cost-row">
                    <span style="font-weight: 600; color: #333333;">Total to repay:</span>
                    <span style="font-weight: 600; color: #333333;">R{cost_details['total']:.2f}</span>
                </div>
            </div>
            {f'<p class="compact" style="margin: 10px 0 0 0; color: #00A651;">ℹ️ Using {cost_details["grace_used"]} grace day(s)</p>' if cost_details['grace_used'] > 0 else ''}
        </div>
        """, unsafe_allow_html=True)
    else:
        st.markdown(f"""
        <div class="warning-card">
            <p class="danger-text">⚠️ Escalation Scenario</p>
            <p class="grey-text">Your expected inflow is on {user_data['inflow_date'].strftime('%d %b')} (day {inflow_days}).<br>
            Grace period ends day {grace_end_days} ({(current_date + datetime.timedelta(days=grace_end_days)).strftime('%d %b')}).</p>
            <p style="font-weight: bold; margin-top: 10px;">Since {st.session_state.selected_days} days exceeds grace period:</p>
            <p class="grey-text">Interest (Standard OD rate): <span class="danger-text">R{cost_details['interest']:.2f}</span></p>
            <p class="grey-text">Activation fee: <span class="danger-text">R{cost_details['activation_fee']:.2f}</span></p>
            <hr>
            <p style="font-weight: bold;">Total cost: <span class="danger-text">R{cost_details['total']:.2f}</span></p>
            <p class="danger-text compact">⚠️ At {cost_details['rate']:.2f}% p.a. (Standard overdraft)</p>
        </div>
        """, unsafe_allow_html=True)
    
    # Comparison table - FNB style
    st.markdown('<p style="font-weight: 600; color: #333333; margin: 20px 0 10px 0;">Compare scenarios:</p>', unsafe_allow_html=True)
    
    comparison_html = '<div class="fnb-card"><div class="cost-table">'
    for days in [3, 7, 14, 30]:
        scenario = calculate_full_cost(st.session_state.selected_amount, days)
        is_selected = days == st.session_state.selected_days
        warning = " ⚠️" if scenario['scenario'] == 'escalated' else ""
        
        row_class = 'cost-row'
        if days == 30:
            row_class += '" style="border-bottom: none;'
        
        label_style = "font-weight: 600;" if is_selected else ""
        value_color = "#E31E24" if scenario['scenario'] == 'escalated' else ("#FF9900" if is_selected else "#666666")
        
        arrow = "→ " if is_selected else ""
        comparison_html += f'''
        <div class="{row_class}">
            <span style="{label_style} color: #333333;">{arrow}{days} days{warning}</span>
            <span style="{label_style} color: {value_color};">R{scenario["total"]:.2f}</span>
        </div>
        '''
    
    comparison_html += '</div>'
    comparison_html += '<p class="compact" style="margin: 10px 0 0 0;">⚠️ = Escalated to standard overdraft</p>'
    comparison_html += '</div>'
    
    st.markdown(comparison_html, unsafe_allow_html=True)
    
    # Predicted inflow - FNB info card style
    days_until = (user_data['inflow_date'] - current_date).days
    st.markdown(f"""
    <div class="info-card">
        <p class="gold-text" style="margin: 0 0 5px 0; font-size: 15px;">📅 Next predicted inflow: {user_data['inflow_date'].strftime('%d %B')}</p>
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
    
    st.markdown("### What if things go wrong?")
    st.markdown('<p class="grey-text">We\'ve got you covered with transparent processes</p>', unsafe_allow_html=True)
    
    # Grace Period - FNB card style
    st.markdown(f"""
    <div class="fnb-card">
        <p style="font-size: 16px; margin: 0 0 10px 0;"><span style="font-size: 20px;">🕐</span> <span class="gold-text">Grace Period</span></p>
        <p class="grey-text" style="margin: 0; line-height: 1.6;">If your predicted inflow doesn't arrive on time, you get an automatic 3-day grace period with no additional fees. We understand that salary dates can shift.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Escalation - FNB card style
    st.markdown(f"""
    <div class="fnb-card">
        <p style="font-size: 16px; margin: 0 0 10px 0;"><span style="font-size: 20px;">📊</span> <span class="gold-text">Escalation to Standard Overdraft</span></p>
        <p class="grey-text" style="margin: 0; line-height: 1.6;">After the grace period, if still unpaid, BufferShield converts to a standard overdraft facility at {user_data['standard_rate']}% p.a. No surprise fees—you'll know exactly what changes.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Communication - FNB card style
    st.markdown("""
    <div class="fnb-card">
        <p style="font-size: 16px; margin: 0 0 10px 0;"><span style="font-size: 20px;">💬</span> <span class="green-text">Proactive Communication</span></p>
        <p class="grey-text" style="margin: 0; line-height: 1.6;">We'll notify you:<br>
        • 2 days before expected repayment<br>
        • On repayment day<br>
        • If grace period activates<br>
        • Before any rate changes<br><br>
        You're always in control via the FNB App.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Fee Transparency - highlighted card
    st.markdown(f"""
    <div class="fnb-card" style="background: linear-gradient(to right, #FF9900 0%, #FF8800 100%); color: white;">
        <p style="font-size: 16px; margin: 0 0 10px 0; color: white;"><span style="font-size: 20px;">💵</span> <span style="font-weight: 600;">Fee Transparency</span></p>
        <p style="color: white; margin: 0; line-height: 1.6; opacity: 0.95;">
        Current BufferShield rate: {user_data['interest_rate']}% p.a.<br>
        Standard overdraft rate: {user_data['standard_rate']}% p.a.<br>
        Activation fee: R0.00<br>
        Monthly fee: R0.00<br><br>
        <strong>No hidden costs. Ever.</strong></p>
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
    
    st.markdown("### Review Details")
    
    # Summary card - FNB orange gradient
    st.markdown(f"""
    <div class="fnb-card" style="background: linear-gradient(to bottom, #FF9900 0%, #FF8800 100%); color: white; text-align: center; padding: 30px 20px;">
        <p style="color: white; margin: 0 0 10px 0; opacity: 0.9; font-size: 14px;">Bridging amount</p>
        <h1 style="color: white; margin: 10px 0 20px 0; font-size: 42px; font-weight: 700;">R{st.session_state.selected_amount:,}</h1>
        <div style="height: 2px; background: white; opacity: 0.3; margin: 20px auto; width: 80px;"></div>
        <p style="color: white; margin: 10px 0 0 0; font-size: 15px;">Expected repay: <strong>{st.session_state.selected_days} days</strong></p>
    </div>
    """, unsafe_allow_html=True)
    
    # Cost breakdown - FNB clean table style
    cost_details = calculate_full_cost(st.session_state.selected_amount, st.session_state.selected_days)
    
    cost_html = '<div class="fnb-card"><p style="font-weight: 600; color: #333333; margin: 0 0 15px 0;">💰 Total cost breakdown</p>'
    cost_html += '<div class="cost-table">'
    
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
    
    for label, value, is_warning in items:
        color = "#E31E24" if is_warning else "#666666"
        value_color = "#E31E24" if is_warning else "#333333"
        cost_html += f'''
        <div class="cost-row" style="border-bottom: 1px solid #F0F0F0;">
            <span style="color: {color};">{label}</span>
            <span style="font-weight: 600; color: {value_color};">{value}</span>
        </div>
        '''
    
    # Total
    total_color = "#E31E24" if cost_details['scenario'] == 'escalated' else "#333333"
    cost_html += f'''
    <div class="cost-row" style="border-top: 2px solid #333333; border-bottom: none; margin-top: 10px; padding-top: 12px;">
        <span style="font-weight: 600; color: #333333;">Total repayment</span>
        <span style="font-weight: 700; color: {total_color}; font-size: 18px;">R{cost_details['total']:.2f}</span>
    </div>
    '''
    
    cost_html += '</div>'  # Close cost-table
    
    # Escalation warning if applicable
    if cost_details['scenario'] == 'escalated':
        cost_html += f'<p class="red-text compact" style="margin: 12px 0 0 0;">⚠️ Escalates to standard overdraft on {cost_details["escalation_date"].strftime("%d %b")}</p>'
    
    cost_html += '</div>'  # Close fnb-card
    
    st.markdown(cost_html, unsafe_allow_html=True)
    
    # Auto-repay - FNB info card
    st.markdown(f"""
    <div class="info-card">
        <p class="gold-text" style="margin: 0 0 8px 0; font-size: 15px;">🔄 Auto-Repay</p>
        <p class="grey-text" style="margin: 0 0 3px 0;">Date: {user_data['inflow_date'].strftime('%d %B %Y')}</p>
        <p class="grey-text" style="margin: 0;">Amount: R{cost_details['total']:.2f} from predicted inflow</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Terms
    st.markdown('<p class="compact" style="text-align: center;">By activating, you agree to BufferShield terms.<br>Funds available immediately after confirmation.</p>', unsafe_allow_html=True)
    
    # Action buttons
    if st.button("✓ Activate BufferShield", key="activate", use_container_width=True):
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
    
    if st.button("Decline Offer", key="decline"):
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
