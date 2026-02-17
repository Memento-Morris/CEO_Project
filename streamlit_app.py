import streamlit as st
import datetime
import math

# Page config with forced light theme
st.set_page_config(
    page_title="FNB PaySure",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# Initialize session state
if 'page' not in st.session_state:
    st.session_state.page = 0
if 'shortfall_amount' not in st.session_state:
    st.session_state.shortfall_amount = 800
if 'expected_repay_days' not in st.session_state:
    st.session_state.expected_repay_days = 7
if 'unread_count' not in st.session_state:
    st.session_state.unread_count = 1
if 'protection_activated' not in st.session_state:
    st.session_state.protection_activated = False

# Get today's date
current_date = datetime.date.today()

# User data - FusionAspire account
user_data = {
    "name": "John Doe",
    "account_number": "****7823",
    "current_balance": 450.00,
    "inflow_date": current_date + datetime.timedelta(days=7),
    "predicted_inflow": 18500,
    
    # Debit order info
    "debit_order_amount": 1250.00,
    "debit_order_date": current_date + datetime.timedelta(days=2),
    "debit_order_recipient": "DStv",
    "predicted_shortfall": 800.00,
    
    # RCI factors
    "income_stability_score": 0.92,
    "debit_success_ratio": 0.88,
    "overdraft_utilization": 0.35,
    "savings_buffer_ratio": 0.15,
    "credit_repayment_performance": 0.95,
    
    # Credit facilities
    "overdraft_limit": 2000,
    "overdraft_rate": 18.25,
    "overdraft_monthly_fee": 69.00,
    
    "temp_loan_rate": 19.75,
    "temp_loan_max": 5000,
}

# ==================== BACKEND LOGIC ====================

def calculate_credit_cost(amount, days, rate):
    """Calculate credit cost"""
    daily_rate = rate / 100 / 365
    total = amount * math.pow(1 + daily_rate, days)
    interest = total - amount
    return {
        'interest': round(interest, 2),
        'total': round(total, 2)
    }

def calculate_rci(user_data, days=0):
    """Calculate RCI with time horizon risk adjustment"""
    weights = {
        'income_stability': 0.30,
        'debit_success': 0.25,
        'overdraft_discipline': 0.20,
        'savings_buffer': 0.15,
        'credit_performance': 0.10
    }
    
    overdraft_score = 1 - user_data['overdraft_utilization']
    
    base_rci = (
        user_data['income_stability_score'] * weights['income_stability'] +
        user_data['debit_success_ratio'] * weights['debit_success'] +
        overdraft_score * weights['overdraft_discipline'] +
        user_data['savings_buffer_ratio'] * weights['savings_buffer'] +
        user_data['credit_repayment_performance'] * weights['credit_performance']
    )
    
    if days > 0:
        decay_factor = 0.005
        time_penalty = min(days * decay_factor, 0.20)
        adjusted_rci = base_rci - time_penalty
    else:
        adjusted_rci = base_rci
    
    return round(max(adjusted_rci, 0.30), 2)

def get_rci_tier(rci):
    """Determine RCI tier"""
    if rci >= 0.85:
        return 1, "Excellent", "● Tier 1", "#00A651"
    elif rci >= 0.70:
        return 2, "Good", "● Tier 2", "#007c7f"
    elif rci >= 0.55:
        return 3, "Fair", "● Tier 3", "#FF9900"
    else:
        return 4, "Low", "● Tier 4", "#E31E24"

def get_credit_options(shortfall, days, user_data, rci_tier):
    """Get all credit options"""
    options = []
    
    # Overdraft
    if shortfall <= user_data['overdraft_limit']:
        od_cost = calculate_credit_cost(shortfall, days, user_data['overdraft_rate'])
        od_fee = user_data['overdraft_monthly_fee'] if shortfall >= 200 else 0
        od_total = od_cost['total'] + od_fee
        
        options.append({
            'name': 'Overdraft',
            'amount': shortfall,
            'days': days,
            'rate': user_data['overdraft_rate'],
            'interest': od_cost['interest'],
            'total': od_cost['total'],
            'fees': od_fee,
            'grand_total': od_total,
            'optimal_for': 'Very short gaps (1-3 days)',
            'is_easy_account': True
        })
    
    # Temporary Loan
    if shortfall <= user_data['temp_loan_max'] and rci_tier <= 3:
        tl_cost = calculate_credit_cost(shortfall, days, user_data['temp_loan_rate'])
        initiation_fee = max(50, shortfall * 0.02)
        
        options.append({
            'name': 'Temporary Loan',
            'amount': shortfall,
            'days': days,
            'rate': user_data['temp_loan_rate'],
            'interest': tl_cost['interest'],
            'total': tl_cost['total'],
            'fees': initiation_fee,
            'grand_total': tl_cost['total'] + initiation_fee,
            'optimal_for': 'Longer gaps (30+ days)',
            'is_easy_account': True
        })
    
    return options

def get_recommended_option(options, shortfall, days, rci_tier):
    """Get recommended option"""
    if not options:
        return None
    
    od_options = [opt for opt in options if 'Overdraft' in opt['name']]
    loan_options = [opt for opt in options if 'Temporary Loan' in opt['name']]
    
    if days <= 10 and od_options:
        return od_options[0]
    
    if (days > 30 or rci_tier >= 3) and loan_options:
        return loan_options[0]
    
    return min(options, key=lambda x: x['grand_total'])

# ==================== PAGE 0 - MESSAGES ====================

def show_message_screen():
    st.markdown("### Messages")
    st.caption("Important updates for you")
    
    st.divider()
    
    st.markdown("#### Today")
    
    with st.container():
        st.error("**Payment Protection Available**")
        st.write(f"**{user_data['debit_order_recipient']}** payment of R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}")
        st.caption(f"We can cover the R{user_data['predicted_shortfall']:,.2f} shortfall for you.")
    
    if st.button("View Protection", use_container_width=True, type="primary"):
        st.session_state.unread_count = 0
        st.session_state.page = 1
        st.rerun()
    
    st.divider()
    
    st.markdown("#### Earlier")
    
    with st.container():
        st.info("**Cashflow Insight**")
        st.caption("R2,450 spent on groceries this month vs R2,100 last month")

# ==================== PAGE 1 - PROTECTION SCREEN ====================

def show_protection_screen():
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_icon, tier_color = get_rci_tier(rci_score)
    
    options = get_credit_options(shortfall, days, user_data, rci_tier)
    recommended = get_recommended_option(options, shortfall, days, rci_tier)
    
    st.markdown("# We'll protect your payment")
    
    # Use Streamlit components instead of raw HTML
    with st.container():
        st.markdown("---")
        
        col1, col2, col3 = st.columns([1, 2, 1])
        with col2:
            st.markdown("##### Payment")
            st.markdown(f"### {user_data['debit_order_recipient']}")
            
            st.markdown("")
            st.markdown("##### Amount covered")
            st.markdown(f"# R{int(shortfall)}")
            
            st.markdown("")
            st.markdown("##### Repay on")
            st.markdown(f"### {user_data['inflow_date'].strftime('%d %B')}")
            
            st.markdown("---")
            
            st.markdown("##### Total cost")
            st.markdown(f"# :green[R{int(recommended['grand_total'] - shortfall)}]")
        
        st.markdown("---")
    
    st.markdown("")
    
    if st.button("Protect my payment", use_container_width=True, type="primary", key="protect_btn"):
        st.session_state.protection_activated = True
        st.session_state.page = 2
        st.rerun()
    
    if st.button("See other options", use_container_width=True, key="options_link"):
        st.session_state.page = 3
        st.rerun()
    
    if st.button("← Back to Messages", use_container_width=True, key="back_msg"):
        st.session_state.page = 0
        st.rerun()

# ==================== PAGE 2 - CONFIRMATION ====================

def show_confirmation_screen():
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_icon, tier_color = get_rci_tier(rci_score)
    
    options = get_credit_options(shortfall, days, user_data, rci_tier)
    recommended = get_recommended_option(options, shortfall, days, rci_tier)
    
    st.balloons()
    
    st.markdown("# :green[Your payment is secured]")
    
    with st.container():
        st.success(f"""
        **{user_data['debit_order_recipient']}** payment will go through on {user_data['debit_order_date'].strftime('%d %B')}.
        
        **We'll automatically repay:**
        - Amount: R{recommended['grand_total']:.2f}
        - Date: {user_data['inflow_date'].strftime('%d %B %Y')}
        - From: Next salary deposit
        
        You're all set. Nothing more to do.
        """)
    
    st.markdown("")
    
    if st.button("Done", use_container_width=True, type="primary"):
        st.session_state.page = 0
        st.rerun()
    
    if st.button("View details", use_container_width=True, key="view_details"):
        st.session_state.page = 3
        st.rerun()

# ==================== PAGE 3 - OPTIONS ====================

def show_options_screen():
    st.markdown("### Compare Options")
    st.caption("All costs shown")
    
    st.divider()
    
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_icon, tier_color = get_rci_tier(rci_score)
    
    options = get_credit_options(shortfall, days, user_data, rci_tier)
    recommended = get_recommended_option(options, shortfall, days, rci_tier)
    
    easy_account_options = [opt for opt in options if opt.get('is_easy_account', True)]
    
    for opt in easy_account_options:
        is_recommended = recommended and opt['name'] == recommended['name']
        
        if is_recommended:
            st.success(f"**Recommended: {opt['name']}**")
        else:
            st.info(f"**{opt['name']}**")
        
        col1, col2 = st.columns([2, 1])
        with col1:
            st.write("Amount:")
            st.write(f"Interest ({opt['days']} days):")
            if opt['fees'] > 0:
                st.write("Fees:")
            st.write("**Total to repay:**")
        with col2:
            st.write(f"R{opt['amount']:,.2f}")
            st.write(f"R{opt['interest']:.2f}")
            if opt['fees'] > 0:
                st.write(f"R{opt['fees']:.2f}")
            st.write(f"**R{opt['grand_total']:,.2f}**")
        
        st.caption(f"**Best for:** {opt['optimal_for']}")
        st.divider()
    
    with st.expander("How we chose this option"):
        st.write(f"""
        **Your Repayment Certainty Index (RCI): {rci_score}**
        
        We calculated your likelihood of successful repayment based on:
        - Income stability: {int(user_data['income_stability_score']*100)}%
        - Payment history: {int(user_data['debit_success_ratio']*100)}%
        - Credit behavior: {int(user_data['credit_repayment_performance']*100)}%
        
        Combined with your {days}-day repayment window, we recommend **{recommended['name']}** as the lowest-cost option that matches your profile.
        """)
    
    st.markdown("")
    
    if st.button("← Back", use_container_width=True):
        st.session_state.page = 1
        st.rerun()

# ==================== PAGE 4 - CALCULATOR ====================

def show_calculator_screen():
    st.markdown("### Cost Calculator")
    st.caption("Explore different scenarios")
    
    st.divider()
    
    st.info("**Exploratory tool** - Try different amounts and timeframes to see costs.")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.markdown("**Amount**")
        calc_amount = st.slider(
            "Amount (R)",
            min_value=100,
            max_value=5000,
            value=int(st.session_state.shortfall_amount),
            step=50,
            key="calc_amount",
            label_visibility="collapsed"
        )
        st.metric("You'll borrow", f"R{calc_amount:,}")
    
    with col2:
        st.markdown("**Days**")
        calc_days = st.slider(
            "Days",
            min_value=1,
            max_value=60,
            value=st.session_state.expected_repay_days,
            step=1,
            key="calc_days",
            label_visibility="collapsed"
        )
        st.metric("Repay in", f"{calc_days} days")
    
    st.divider()
    
    rci_score = calculate_rci(user_data, days=calc_days)
    rci_tier, rci_label, rci_icon, tier_color = get_rci_tier(rci_score)
    
    calc_options = get_credit_options(calc_amount, calc_days, user_data, rci_tier)
    calc_recommended = get_recommended_option(calc_options, calc_amount, calc_days, rci_tier)
    
    easy_calc_options = [opt for opt in calc_options if opt.get('is_easy_account', True)]
    
    for opt in easy_calc_options:
        is_recommended = calc_recommended and opt['name'] == calc_recommended['name']
        
        if is_recommended:
            st.success(f"**{opt['name']} (Recommended)**")
        else:
            st.info(f"**{opt['name']}**")
        
        st.metric("Total to repay", f"R{opt['grand_total']:,.2f}")
        st.caption(opt['optimal_for'])
        st.divider()
    
    if st.button("← Back to Messages", use_container_width=True):
        st.session_state.page = 0
        st.rerun()

# ==================== MAIN ROUTING ====================

if st.session_state.page == 0:
    show_message_screen()
elif st.session_state.page == 1:
    show_protection_screen()
elif st.session_state.page == 2:
    show_confirmation_screen()
elif st.session_state.page == 3:
    show_options_screen()
elif st.session_state.page == 4:
    show_calculator_screen()
