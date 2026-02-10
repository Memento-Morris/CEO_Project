import streamlit as st
import datetime

# Page config
st.set_page_config(
    page_title="FNB BufferShield",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# Custom CSS for FNB branding
st.markdown("""
<style>
    /* FNB Colors */
    :root {
        --fnb-dark-grey: #2C3E50;
        --fnb-orange: #FF6B00;
        --fnb-teal: #00A9CE;
        --fnb-gold: #F9A01B;
    }
    
    /* Hide Streamlit branding */
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
    header {visibility: hidden;}
    
    /* Custom header */
    .fnb-header {
        background-color: var(--fnb-dark-grey);
        padding: 20px;
        border-radius: 10px;
        margin-bottom: 20px;
        text-align: center;
    }
    
    .fnb-header h1 {
        color: white;
        margin: 0;
        font-size: 24px;
    }
    
    .fnb-header p {
        color: var(--fnb-gold);
        margin: 5px 0 0 0;
        font-size: 14px;
    }
    
    /* Card styling */
    .card {
        background: #F9FAFB;
        padding: 15px;
        border-radius: 8px;
        border: 1px solid #D1D5DB;
        margin: 10px 0;
        color: #1F2937;
    }
    
    .notification-card {
        background: #F9FAFB;
        padding: 15px;
        border-radius: 8px;
        border: 1px solid #D1D5DB;
        margin: 10px 0;
        cursor: pointer;
        transition: box-shadow 0.3s;
    }
    
    .notification-card:hover {
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    
    /* Warning card */
    .warning-card {
        background: #FEF2F2;
        padding: 15px;
        border-radius: 8px;
        border: 2px solid #EF4444;
        margin: 15px 0;
    }
    
    /* Text colors */
    .orange-text {
        color: var(--fnb-orange);
        font-weight: bold;
    }
    
    .teal-text {
        color: var(--fnb-teal);
        font-weight: bold;
    }
    
    .danger-text {
        color: #EF4444;
        font-weight: bold;
    }
    
    .grey-text {
        color: #6B7280;
        font-size: 14px;
    }
    
    /* Progress dots */
    .progress-dots {
        display: flex;
        justify-content: center;
        align-items: center;
        margin: 20px 0;
        gap: 8px;
    }
    
    .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: #E0E3E8;
    }
    
    .dot.active {
        background: var(--fnb-dark-grey);
        width: 12px;
        height: 12px;
    }
    
    .dot.completed {
        background: var(--fnb-gold);
    }
    
    /* Buttons */
    .stButton > button {
        width: 100%;
        background-color: var(--fnb-dark-grey);
        color: white;
        border: none;
        padding: 15px;
        font-size: 16px;
        font-weight: bold;
        border-radius: 8px;
    }
    
    .stButton > button:hover {
        background-color: #1a252f;
    }
    
    /* Amount display */
    .amount-display {
        text-align: center;
        font-size: 48px;
        font-weight: bold;
        color: var(--fnb-dark-grey);
        margin: 20px 0;
    }
    
    /* Compact text */
    .compact {
        font-size: 12px;
        color: #6B7280;
    }
    
    /* Info card with light background */
    .info-card {
        background: #EFF6FF;
        padding: 15px;
        border-radius: 8px;
        border: 1px solid #BFDBFE;
        margin: 10px 0;
        color: #1E40AF;
    }
    
    /* Success card */
    .success-card {
        background: #F0FDF4;
        padding: 15px;
        border-radius: 8px;
        border: 1px solid #BBF7D0;
        margin: 10px 0;
        color: #166534;
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
    """Display progress dots"""
    dots_html = '<div class="progress-dots">'
    for i in range(1, total_steps + 1):
        if i < current_step:
            dots_html += '<div class="dot completed"></div>'
        elif i == current_step:
            dots_html += '<div class="dot active"></div>'
        else:
            dots_html += '<div class="dot"></div>'
        
        if i < total_steps:
            dots_html += '<div style="width: 30px; height: 2px; background: {}"></div>'.format(
                '#F9A01B' if i < current_step else '#E0E3E8'
            )
    
    dots_html += '</div>'
    st.markdown(dots_html, unsafe_allow_html=True)

# Page 0: Notification Screen
def show_notification_screen():
    st.markdown("""
    <div class="fnb-header">
        <h1>Notifications</h1>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown("#### Today")
    
    # Notification 1: Action Required
    if st.button("⚠️ **Action Required: Upcoming Debit Order**\n\n"
                 f"{user_data['debit_order_recipient']} • R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}\n\n"
                 "Predicted shortfall detected. BufferShield available.", 
                 key="notif1", use_container_width=True):
        st.session_state.page = 1
        st.rerun()
    
    # Notification 2: Reschedule suggestion
    st.button(f"📅 **Suggested: Reschedule Debit Order**\n\n"
              f"{user_data['debit_order_recipient']} debit order\n\n"
              "Move to after your next inflow for better cashflow",
              key="notif2", use_container_width=True)
    
    st.markdown("#### Yesterday")
    
    # Notification 3: Insight
    st.button("📊 **Cashflow Insight**\n\n"
              "Your spending pattern detected\n\n"
              "R2,450 spent on groceries this month vs R2,100 last month",
              key="notif3", use_container_width=True)

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
    <div class="card">
        <p class="compact">⚡ Not available if used twice in 30 days • Currently: {user_data['activations_used']}/2</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Why you qualify
    st.markdown(f"""
    <div class="info-card">
        <p style="font-weight: bold; color: #1E40AF;">🔮 Why you qualify</p>
        <p style="color: #1E40AF;">{user_data['flagged_reason']}: {user_data['debit_order_recipient']} R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}</p>
        <p class="danger-text compact">Predicted shortfall: R{user_data['predicted_shortfall']:,.2f}</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown("### Bridging amount needed?")
    
    # Amount display
    st.markdown(f'<div class="amount-display">R{st.session_state.selected_amount:,}</div>', unsafe_allow_html=True)
    
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
    
    # Next inflow info
    st.markdown(f"""
    <div class="success-card">
        <p style="color: #166534; text-align: center; font-weight: bold;">Next expected inflow</p>
        <p style="text-align: center; font-size: 18px; font-weight: bold; color: #15803D;">R{user_data['predicted_inflow']:,}</p>
        <p style="text-align: center; color: #166534;">{user_data['inflow_date'].strftime('%d %B %Y')}</p>
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
        <div class="card">
            <p style="font-weight: bold; color: #1F2937;">💰 Cost for selected period</p>
            <p style="color: #1F2937;">{st.session_state.selected_days} days: <span class="orange-text">R{cost_details['interest']:.2f}</span></p>
            <p style="color: #1F2937;">Total to repay: <span style="font-weight: bold;">R{cost_details['total']:.2f}</span></p>
            {f'<p class="teal-text compact">ℹ️ Using {cost_details["grace_used"]} grace day(s)</p>' if cost_details['grace_used'] > 0 else ''}
        </div>
        """, unsafe_allow_html=True)
    else:
        st.markdown(f"""
        <div class="warning-card">
            <p class="danger-text">⚠️ Escalation Scenario</p>
            <p style="color: #991B1B;">Your expected inflow is on {user_data['inflow_date'].strftime('%d %b')} (day {inflow_days}).<br>
            Grace period ends day {grace_end_days} ({(current_date + datetime.timedelta(days=grace_end_days)).strftime('%d %b')}).</p>
            <p style="font-weight: bold; margin-top: 10px; color: #991B1B;">Since {st.session_state.selected_days} days exceeds grace period:</p>
            <p style="color: #991B1B;">Interest (Standard OD rate): <span class="danger-text">R{cost_details['interest']:.2f}</span></p>
            <p style="color: #991B1B;">Activation fee: <span class="danger-text">R{cost_details['activation_fee']:.2f}</span></p>
            <hr>
            <p style="font-weight: bold; color: #991B1B;">Total cost: <span class="danger-text">R{cost_details['total']:.2f}</span></p>
            <p class="danger-text compact">⚠️ At {cost_details['rate']:.2f}% p.a. (Standard overdraft)</p>
        </div>
        """, unsafe_allow_html=True)
    
    # Comparison table
    st.markdown("**Compare scenarios:**")
    
    comparison_html = '<div class="card">'
    for days in [3, 7, 14, 30]:
        scenario = calculate_full_cost(st.session_state.selected_amount, days)
        is_selected = days == st.session_state.selected_days
        warning = "⚠️" if scenario['scenario'] == 'escalated' else ""
        style = "font-weight: bold;" if is_selected else ""
        color = "#EF4444" if scenario['scenario'] == 'escalated' else ("#FF6B00" if is_selected else "#6B7280")
        
        arrow = "→ " if is_selected else "   "
        comparison_html += f'<p style="{style}color: {color};">{arrow}{days} days {warning} <span style="float: right;">R{scenario["total"]:.2f}</span></p>'
    
    comparison_html += '<p class="compact">⚠️ = Escalated to standard overdraft</p>'
    comparison_html += '</div>'
    
    st.markdown(comparison_html, unsafe_allow_html=True)
    
    # Predicted inflow
    days_until = (user_data['inflow_date'] - current_date).days
    st.markdown(f"""
    <div class="info-card">
        <p style="font-weight: bold; color: #1E40AF;">📅 Next predicted inflow: {user_data['inflow_date'].strftime('%d %B')}</p>
        <p style="color: #1E40AF;">in {days_until} days • We'll auto-repay from this</p>
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
    
    # Grace Period
    st.markdown(f"""
    <div class="card">
        <p style="font-size: 18px; color: #1F2937;">🕐 <span class="teal-text">Grace Period</span></p>
        <p class="grey-text">If your predicted inflow doesn't arrive on time, you get an automatic 3-day grace period with no additional fees. We understand that salary dates can shift.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Escalation
    st.markdown(f"""
    <div class="card">
        <p style="font-size: 18px; color: #1F2937;">📊 <span class="orange-text">Escalation to Standard Overdraft</span></p>
        <p class="grey-text">After the grace period, if still unpaid, BufferShield converts to a standard overdraft facility at {user_data['standard_rate']}% p.a. No surprise fees—you'll know exactly what changes.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Communication
    st.markdown("""
    <div class="card">
        <p style="font-size: 18px; color: #1F2937;">💬 <span style="color: #15803D; font-weight: bold;">Proactive Communication</span></p>
        <p class="grey-text">We'll notify you:<br>
        • 2 days before expected repayment<br>
        • On repayment day<br>
        • If grace period activates<br>
        • Before any rate changes<br><br>
        You're always in control via the FNB App.</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Fee Transparency
    st.markdown(f"""
    <div class="info-card">
        <p style="font-size: 18px; color: #1E40AF;">💵 <span style="font-weight: bold;">Fee Transparency</span></p>
        <p style="color: #1E40AF;">Current BufferShield rate: {user_data['interest_rate']}% p.a.<br>
        Standard overdraft rate: {user_data['standard_rate']}% p.a.<br>
        Activation fee: R0.00<br>
        Monthly fee: R0.00<br><br>
        No hidden costs. Ever.</p>
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
    
    # Summary card
    st.markdown(f"""
    <div class="card" style="background: #2C3E50; text-align: center;">
        <p style="color: #F9A01B;">Bridging amount</p>
        <h1 style="color: white; margin: 10px 0;">R{st.session_state.selected_amount:,}</h1>
        <hr style="border-color: #F9A01B;">
        <p style="color: white;">Expected repay: <strong>{st.session_state.selected_days} days</strong></p>
    </div>
    """, unsafe_allow_html=True)
    
    # Cost breakdown
    cost_details = calculate_full_cost(st.session_state.selected_amount, st.session_state.selected_days)
    
    cost_html = '<div class="card"><p style="font-weight: bold; color: #1F2937;">💰 Total cost breakdown</p><br>'
    
    if cost_details['scenario'] == 'on_time':
        cost_html += f'<p class="grey-text">Bridging amount <span style="float: right; color: #1F2937; font-weight: bold;">R{st.session_state.selected_amount:,.2f}</span></p>'
        cost_html += f'<p class="grey-text">Interest charge <span style="float: right; color: #1F2937; font-weight: bold;">R{cost_details["interest"]:.2f}</span></p>'
        cost_html += f'<p class="grey-text">Rate <span style="float: right; color: #1F2937; font-weight: bold;">{cost_details["rate"]:.2f}% p.a. (BufferShield)</span></p>'
        cost_html += f'<p class="grey-text">Activation fee <span style="float: right; color: #1F2937; font-weight: bold;">R0.00</span></p>'
        cost_html += f'<p class="grey-text">Monthly fee <span style="float: right; color: #1F2937; font-weight: bold;">R0.00</span></p>'
        if cost_details['grace_used'] > 0:
            cost_html += f'<p class="grey-text">Grace period used <span style="float: right; color: #1F2937; font-weight: bold;">{cost_details["grace_used"]} day(s)</span></p>'
    else:
        cost_html += f'<p class="grey-text">Bridging amount <span style="float: right; color: #1F2937; font-weight: bold;">R{st.session_state.selected_amount:,.2f}</span></p>'
        cost_html += f'<p class="danger-text">Interest charge <span style="float: right;">R{cost_details["interest"]:.2f}</span></p>'
        cost_html += f'<p class="danger-text">Rate <span style="float: right;">{cost_details["rate"]:.2f}% p.a. (Standard OD)</span></p>'
        cost_html += f'<p class="danger-text">Activation fee <span style="float: right;">R{cost_details["activation_fee"]:.2f}</span></p>'
        cost_html += f'<p class="danger-text">Grace period exceeded <span style="float: right;">by {cost_details["days_beyond_grace"]} day(s)</span></p>'
    
    cost_html += '<hr>'
    
    total_color = "#EF4444" if cost_details['scenario'] == 'escalated' else "#2C3E50"
    cost_html += f'<p style="font-size: 18px; font-weight: bold; color: #1F2937;">Total repayment <span style="float: right; color: {total_color};">R{cost_details["total"]:.2f}</span></p>'
    
    if cost_details['scenario'] == 'escalated':
        cost_html += f'<p class="danger-text compact">⚠️ Escalates to standard overdraft on {cost_details["escalation_date"].strftime("%d %b")}</p>'
    
    cost_html += '</div>'
    
    st.markdown(cost_html, unsafe_allow_html=True)
    
    # Auto-repay
    st.markdown(f"""
    <div class="info-card">
        <p style="font-weight: bold; color: #1E40AF;">🔄 Auto-Repay</p>
        <p style="color: #1E40AF;">Date: {user_data['inflow_date'].strftime('%d %B %Y')}</p>
        <p style="color: #1E40AF;">Amount: R{cost_details['total']:.2f} from predicted inflow</p>
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
