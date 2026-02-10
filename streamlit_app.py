import streamlit as st
import datetime
import time
import math

# Page config
st.set_page_config(
    page_title="FNB BufferShield",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# Custom CSS for FNB branding - light grey theme with correct teal accents
st.markdown("""
<style>
    /* FNB Actual Colors - subdued palette */
    :root {
        --fnb-teal: #007c7f;        /* PRIMARY ACCENT - CORRECT TEAL */
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
        padding-bottom: 80px; /* Space for bottom nav */
    }
    
    /* Custom FNB header - subdued grey */
    .fnb-header {
        background: #F5F5F5;
        padding: 25px 20px;
        margin: -1rem -1rem 2rem -1rem;
        border-bottom: 1px solid #E0E0E0;
        text-align: center;
    }
    
    .fnb-header h1 {
        color: #333333;
        margin: 0;
        font-size: 32px;
        font-weight: 600;
    }
    
    .fnb-header p {
        color: #666666;
        margin: 5px 0 0 0;
        font-size: 16px;
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
    
    .message-card {
        background: white;
        padding: 18px;
        border-radius: 12px;
        border: 1px solid #E0E0E0;
        margin: 0;
        cursor: pointer;
        transition: all 0.2s ease;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
        position: relative;
    }
    
    .message-card:hover {
        border-color: #007c7f;
        box-shadow: 0 4px 12px rgba(0, 124, 127, 0.15);
    }
    
    /* Message separator line */
    .message-separator {
        height: 1px;
        background: #E0E0E0;
        margin: 0;
    }
    
    /* Unread badge - orange circle */
    .unread-badge {
        background: #FF9900;
        color: white;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        font-weight: 700;
        flex-shrink: 0;
    }
    
    /* Section headers - OUTSIDE cards */
    .section-header {
        color: #007c7f;
        font-size: 18px;
        font-weight: 600;
        margin: 25px 0 15px 0;
    }
    
    /* Centered section header */
    .centered-header {
        color: #333333;
        font-size: 24px;
        font-weight: 600;
        margin: 25px 0 15px 0;
        text-align: center;
    }
    
    /* Teal subheadings */
    .teal-heading {
        color: #007c7f;
        font-size: 16px;
        font-weight: 600;
        margin: 20px 0 10px 0;
    }
    
    /* Centered teal subheading */
    .centered-teal-heading {
        color: #007c7f;
        font-size: 18px;
        font-weight: 600;
        margin: 20px 0 10px 0;
        text-align: center;
    }
    
    /* Text colors */
    .teal-text {
        color: #007c7f;
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
        background: #007c7f;
        width: 10px;
        height: 10px;
    }
    
    .dot.completed {
        background: #007c7f;
        opacity: 0.5;
    }
    
    .dot-line {
        width: 30px;
        height: 2px;
        background: #E0E0E0;
    }
    
    .dot-line.completed {
        background: #007c7f;
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
        background: #007c7f;
        color: white;
        border: none;
    }
    
    .stButton > button[kind="primary"]:hover,
    .stButton > button.primary-button:hover {
        background: #006a6d;
    }
    
    .stButton > button[kind="primary"]:active,
    .stButton > button.primary-button:active {
        background: #005a5d;
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
        border-left: 3px solid #007c7f;
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
        background: #007c7f;
    }
    
    /* Compact text */
    .compact {
        font-size: 13px;
        color: #666666;
        line-height: 1.5;
    }
    
    /* Checkbox styling */
    .stCheckbox {
        padding: 15px 0;
    }
    
    .stCheckbox > label {
        color: #000000 !important;
        font-size: 14px !important;
        font-weight: 600 !important;
    }
    
    .stCheckbox > label > div[data-testid="stMarkdownContainer"] > p {
        color: #000000 !important;
        font-size: 14px !important;
        font-weight: 600 !important;
    }
    
    .stCheckbox > label span {
        color: #000000 !important;
    }
    
    /* Checkbox input styling */
    input[type="checkbox"] {
        width: 20px !important;
        height: 20px !important;
        cursor: pointer !important;
    }
    
    input[type="checkbox"]:checked {
        accent-color: #007c7f !important;
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
    
    /* Bottom Navigation Bar */
    .bottom-nav {
        position: fixed;
        bottom: 0;
        left: 0;
        right: 0;
        background: white;
        border-top: 1px solid #E0E0E0;
        padding: 8px 0 8px 0;
        display: flex;
        justify-content: space-around;
        align-items: center;
        box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1);
        z-index: 1000;
    }
    
    .nav-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        padding: 8px 16px;
        cursor: pointer;
        transition: all 0.2s ease;
        text-decoration: none;
        color: #666666;
        position: relative;
    }
    
    .nav-item:hover {
        color: #007c7f;
    }
    
    .nav-item.active {
        color: #007c7f;
    }
    
    .nav-icon {
        width: 24px;
        height: 24px;
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    
    .nav-icon svg {
        width: 24px;
        height: 24px;
    }
    
    .nav-label {
        font-size: 11px;
        font-weight: 500;
    }
    
    /* Message badge on nav icon */
    .nav-badge {
        position: absolute;
        top: -6px;
        right: -6px;
        background: #E31E24;
        color: white;
        width: 18px;
        height: 18px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 10px;
        font-weight: 700;
        border: 2px solid white;
        z-index: 10;
    }
    
    /* Hide default streamlit elements */
    div[data-testid="stDecoration"] {
        display: none;
    }
    
    /* Hide navigation button */
    button[aria-label="Go to Messages"],
    button[title="Go to Messages"] {
        position: absolute;
        opacity: 0;
        height: 0;
        width: 0;
        padding: 0;
        margin: 0;
        border: none;
        overflow: hidden;
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
if 'last_message_time' not in st.session_state:
    st.session_state.last_message_time = time.time()
if 'messages' not in st.session_state:
    st.session_state.messages = []
if 'unread_count' not in st.session_state:
    st.session_state.unread_count = 1
if 'terms_accepted' not in st.session_state:
    st.session_state.terms_accepted = False
if 'message_check_count' not in st.session_state:
    st.session_state.message_check_count = 0

# Get today's actual date
current_date = datetime.date.today()

# User data - dates calculated relative to today
user_data = {
    "name": "John Doe",
    "account_number": "****7823",
    "current_balance": 450.00,
    "inflow_date": current_date + datetime.timedelta(days=7),
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
    "debit_order_date": current_date + datetime.timedelta(days=2),
    "debit_order_recipient": "DStv",
    "flagged_reason": "Upcoming debit order",
    "predicted_shortfall": 800.00
}

# Message templates
message_templates = [
    {
        "type": "action",
        "title": "Action Required: Upcoming Debit Order",
        "subtitle": "{} • R{:,.2f} on {}",
        "detail": "Predicted shortfall detected. BufferShield available.",
        "border_color": "#E31E24",
        "is_read": False
    },
    {
        "type": "suggestion",
        "title": "Suggested: Reschedule Debit Order",
        "subtitle": "{} debit order",
        "detail": "Move to after your next inflow for better cashflow",
        "border_color": "#E0E0E0",
        "is_read": True
    },
    {
        "type": "insight",
        "title": "Cashflow Insight",
        "subtitle": "Your spending pattern detected",
        "detail": "R2,450 spent on groceries this month vs R2,100 last month",
        "border_color": "#E0E0E0",
        "is_read": True
    },
    {
        "type": "alert",
        "title": "Low Balance Alert",
        "subtitle": "Account balance below R500",
        "detail": "Consider activating BufferShield for upcoming expenses",
        "border_color": "#FF9900",
        "is_read": True
    },
    {
        "type": "tip",
        "title": "Savings Tip",
        "subtitle": "Round-up feature available",
        "detail": "Save R127.50 extra this month with automatic round-ups",
        "border_color": "#E0E0E0",
        "is_read": True
    },
    {
        "type": "reminder",
        "title": "Payment Reminder",
        "subtitle": "Electricity prepaid running low",
        "detail": "Current balance: 45 units. Top up recommended.",
        "border_color": "#007c7f",
        "is_read": True
    },
    {
        "type": "achievement",
        "title": "Milestone Reached!",
        "subtitle": "You've saved R5,000 this quarter",
        "detail": "Keep up the great work with your savings goals",
        "border_color": "#00A651",
        "is_read": True
    },
    {
        "type": "security",
        "title": "Security Notice",
        "subtitle": "New login detected",
        "detail": "Device: iPhone 14 • Location: Benoni, GP • Just now",
        "border_color": "#007c7f",
        "is_read": True
    }
]

# Helper functions
def get_message_icon(message_type):
    """Get minimal SVG icon for message type with teal circle background"""
    icons = {
        "action": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M20 10 L20 22 L26 16" stroke="#005557" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="20" cy="27" r="1.5" fill="#005557"/></svg>''',
        
        "suggestion": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M15 20 L20 15 L25 20" stroke="#005557" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M20 15 L20 28" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/></svg>''',
        
        "insight": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M20 12 L20 20 L26 20" stroke="#005557" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="20" cy="20" r="7" stroke="#005557" stroke-width="2.5" fill="none"/></svg>''',
        
        "alert": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M20 13 L20 21" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><circle cx="20" cy="26" r="1.5" fill="#005557"/><circle cx="20" cy="20" r="9" stroke="#005557" stroke-width="2.5" fill="none"/></svg>''',
        
        "tip": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M17 23 L20 20 L27 13" stroke="#005557" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M13 19 L17 23" stroke="#005557" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>''',
        
        "reminder": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><circle cx="20" cy="18" r="7" stroke="#005557" stroke-width="2.5" fill="none"/><path d="M20 18 L20 14" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><path d="M20 18 L23 20" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><path d="M17 26 L23 26" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/></svg>''',
        
        "achievement": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><circle cx="20" cy="18" r="6" stroke="#005557" stroke-width="2.5" fill="none"/><path d="M20 24 L20 28" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><path d="M16 28 L24 28" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><path d="M18 28 L18 30" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/><path d="M22 28 L22 30" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/></svg>''',
        
        "security": '''<svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#e6f5f5"/><path d="M20 12 L20 12 C23 12 26 14 26 17 L26 22 C26 25 23 27 20 27 C17 27 14 25 14 22 L14 17 C14 14 17 12 20 12 Z" stroke="#005557" stroke-width="2.5" fill="none" stroke-linejoin="round"/><circle cx="20" cy="20" r="2" fill="#005557"/><path d="M20 22 L20 24" stroke="#005557" stroke-width="2.5" stroke-linecap="round"/></svg>'''
    }
    
    return icons.get(message_type, icons["insight"])

def add_message():
    """Add a new message from templates - with limit to prevent crashes"""
    import random
    current_time = time.time()
    
    # Limit total messages to 15 max to prevent memory issues
    if len(st.session_state.messages) >= 15:
        return
    
    # Check if 5 seconds have passed
    if current_time - st.session_state.last_message_time >= 5:
        # Select a random message template (skip the first one as it's always shown)
        template = random.choice(message_templates[1:])
        
        # Format the message
        if template["type"] == "suggestion":
            subtitle = template["subtitle"].format(user_data['debit_order_recipient'])
        else:
            subtitle = template["subtitle"]
        
        message = {
            "type": template["type"],
            "title": template["title"],
            "subtitle": subtitle,
            "detail": template["detail"],
            "border_color": template["border_color"],
            "timestamp": datetime.datetime.now(),
            "category": "Today",
            "is_read": False
        }
        
        # Add to the beginning of messages list
        st.session_state.messages.insert(0, message)
        st.session_state.last_message_time = current_time
        st.session_state.unread_count += 1

def calculate_compound_interest(principal, rate, days):
    """Calculate compound interest (daily compounding)"""
    daily_rate = rate / 100 / 365
    amount = principal * math.pow(1 + daily_rate, days)
    interest = amount - principal
    return interest

def calculate_full_cost(amount, expected_days):
    """Calculate full cost including grace period and escalation"""
    inflow_days = (user_data['inflow_date'] - current_date).days
    
    if expected_days <= inflow_days + user_data['grace_days']:
        interest = calculate_compound_interest(amount, user_data['interest_rate'], expected_days)
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
        interest = calculate_compound_interest(amount, user_data['standard_rate'], expected_days)
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

def show_bottom_nav(active="messages"):
    """Display bottom navigation bar with minimal black line art icons"""
    unread_badge = f'<span class="nav-badge">{st.session_state.unread_count}</span>' if st.session_state.unread_count > 0 else ''
    
    # Minimal black line art SVG icons
    home_icon = '''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline></svg>'''
    
    # Card icon for bank
    card_icon = '''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="4" width="22" height="16" rx="2" ry="2"></rect><line x1="1" y1="10" x2="23" y2="10"></line></svg>'''
    
    message_icon = '''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>'''
    
    profile_icon = '''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>'''
    
    menu_icon = '''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="12" x2="21" y2="12"></line><line x1="3" y1="6" x2="21" y2="6"></line><line x1="3" y1="18" x2="21" y2="18"></line></svg>'''
    
    nav_html = f"""
    <div class="bottom-nav">
        <div class="nav-item {'active' if active == 'home' else ''}" onclick="return false;">
            <div class="nav-icon">{home_icon}</div>
            <div class="nav-label">Home</div>
        </div>
        <div class="nav-item {'active' if active == 'bank' else ''}" onclick="return false;">
            <div class="nav-icon">{card_icon}</div>
            <div class="nav-label">Bank</div>
        </div>
        <div class="nav-item {'active' if active == 'messages' else ''}" id="nav-messages-item">
            <div class="nav-icon" style="position: relative;">
                {message_icon}
                {unread_badge}
            </div>
            <div class="nav-label">Messages</div>
        </div>
        <div class="nav-item {'active' if active == 'profile' else ''}" onclick="return false;">
            <div class="nav-icon">{profile_icon}</div>
            <div class="nav-label">My Profile</div>
        </div>
        <div class="nav-item {'active' if active == 'menu' else ''}" onclick="return false;">
            <div class="nav-icon">{menu_icon}</div>
            <div class="nav-label">Menu</div>
        </div>
    </div>
    """
    st.markdown(nav_html, unsafe_allow_html=True)
    
    # Add hidden button for messages navigation (only if not on messages page)
    if active != "messages":
        if st.button("", key=f"nav_to_messages_{active}", help="Go to Messages"):
            st.session_state.page = 0
            st.session_state.message_check_count = 0
            # Scroll to top
            st.markdown("""
            <script>
            setTimeout(function() {
                window.parent.document.querySelector('section.main').scrollTo({top: 0, behavior: 'smooth'});
                document.querySelector('section.main').scrollTo({top: 0, behavior: 'smooth'});
            }, 100);
            </script>
            """, unsafe_allow_html=True)
            st.rerun()
    
    # Add JavaScript to handle click on messages nav item
    st.markdown(f"""
    <script>
    document.getElementById('nav-messages-item').addEventListener('click', function() {{
        // Find and click the hidden button
        const buttons = window.parent.document.querySelectorAll('button');
        buttons.forEach(btn => {{
            if (btn.getAttribute('aria-label') === 'Go to Messages' || btn.title === 'Go to Messages') {{
                btn.click();
            }}
        }});
        
        // Also try in current document
        const localButtons = document.querySelectorAll('button');
        localButtons.forEach(btn => {{
            if (btn.getAttribute('aria-label') === 'Go to Messages' || btn.title === 'Go to Messages') {{
                btn.click();
            }}
        }});
    }});
    </script>
    """, unsafe_allow_html=True)

# Page 0: Message Screen
def show_message_screen():
    # Increment check counter and add message periodically (max 3 checks to prevent crashes)
    st.session_state.message_check_count = st.session_state.get('message_check_count', 0) + 1
    
    if st.session_state.message_check_count <= 3:
        add_message()
    
    st.markdown("""
    <div class="fnb-header">
        <h1>Messages</h1>
        <p>Important updates for you</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Show dynamic messages with separators
    if st.session_state.messages:
        st.markdown('<p class="section-header">Recent</p>', unsafe_allow_html=True)
        
        for idx, msg in enumerate(st.session_state.messages[:3]):
            unread_badge = '<div class="unread-badge">1</div>' if not msg['is_read'] else ''
            msg_icon = get_message_icon(msg['type'])
            
            st.markdown(f"""
            <div class="message-card" style="border-left: 3px solid {msg['border_color']};">
                <div style="display: flex; justify-content: space-between; align-items: center; gap: 15px;">
                    <div style="flex-shrink: 0;">
                        {msg_icon}
                    </div>
                    <div style="flex: 1;">
                        <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">{msg['title']}</p>
                        <p class="grey-text" style="margin: 5px 0 0 0;">{msg['subtitle']}</p>
                        <p class="compact" style="margin: 5px 0 0 0;">{msg['detail']}</p>
                        <p class="compact" style="margin: 5px 0 0 0; color: #999999;">{msg['timestamp'].strftime('%H:%M:%S')}</p>
                    </div>
                    {unread_badge}
                </div>
            </div>
            """, unsafe_allow_html=True)
            
            if idx < min(2, len(st.session_state.messages[:3]) - 1):
                st.markdown('<div class="message-separator"></div>', unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Today</p>', unsafe_allow_html=True)
    
    # Primary action message
    unread_badge_main = '<div class="unread-badge">1</div>' if st.session_state.unread_count > 0 else ''
    action_icon = get_message_icon("action")
    
    st.markdown(f"""
    <div class="message-card" style="border-left: 3px solid #E31E24;">
        <div style="display: flex; justify-content: space-between; align-items: center; gap: 15px;">
            <div style="flex-shrink: 0;">
                {action_icon}
            </div>
            <div style="flex: 1;">
                <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">Action Required: Upcoming Debit Order</p>
                <p class="grey-text" style="margin: 5px 0 0 0;">{user_data['debit_order_recipient']} • R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}</p>
                <p class="compact" style="margin: 5px 0 0 0;">Predicted shortfall detected. BufferShield available.</p>
            </div>
            {unread_badge_main}
        </div>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("View BufferShield Offer", key="msg1_btn", use_container_width=True):
        st.session_state.unread_count = max(0, st.session_state.unread_count - 1)
        st.session_state.page = 1
        st.markdown("""
        <script>
        setTimeout(function() {
            window.scrollTo({top: 0, behavior: 'instant'});
            window.parent.document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
            document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
        }, 50);
        </script>
        """, unsafe_allow_html=True)
        st.rerun()
    
    # Show older messages
    if st.session_state.messages and len(st.session_state.messages) > 3:
        st.markdown('<p class="section-header" style="margin-top: 30px;">Earlier</p>', unsafe_allow_html=True)
        
        for idx, msg in enumerate(st.session_state.messages[3:6]):
            msg_icon = get_message_icon(msg.get('type', 'insight'))
            
            st.markdown(f"""
            <div class="message-card">
                <div style="display: flex; justify-content: space-between; align-items: center; gap: 15px;">
                    <div style="flex-shrink: 0;">
                        {msg_icon}
                    </div>
                    <div style="flex: 1;">
                        <p style="margin: 0; font-weight: 600; color: #333333; font-size: 15px;">{msg['title']}</p>
                        <p class="grey-text" style="margin: 5px 0 0 0;">{msg['subtitle']}</p>
                        <p class="compact" style="margin: 5px 0 0 0;">{msg['detail']}</p>
                        <p class="compact" style="margin: 5px 0 0 0; color: #999999;">{msg['timestamp'].strftime('%H:%M:%S')}</p>
                    </div>
                </div>
            </div>
            """, unsafe_allow_html=True)
            
            if idx < min(2, len(st.session_state.messages[3:6]) - 1):
                st.markdown('<div class="message-separator"></div>', unsafe_allow_html=True)
    
    show_bottom_nav(active="messages")
    
    # Only refresh if we haven't exceeded check limit
    if st.session_state.message_check_count <= 3:
        time.sleep(5)
        st.rerun()

# Page 1: Amount Selection
def show_page_1():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(1, 4)
    
    st.markdown(f"""
    <div class="fnb-card" style="background: #F5F5F5;">
        <p class="compact" style="margin: 0;">Not available if used twice in 30 days • Currently: {user_data['activations_used']}/2</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="centered-teal-heading">Why you qualify</p>', unsafe_allow_html=True)
    
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0 0 5px 0;">{user_data['flagged_reason']}: {user_data['debit_order_recipient']} R{user_data['debit_order_amount']:,.2f} on {user_data['debit_order_date'].strftime('%d %b')}</p>
        <p class="red-text compact" style="margin: 0;">Predicted shortfall: R{user_data['predicted_shortfall']:,.2f}</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="centered-teal-heading">Bridging amount needed?</p>', unsafe_allow_html=True)
    
    st.markdown(f'<div class="amount-display"><span class="currency">R</span>{st.session_state.selected_amount:,}</div>', unsafe_allow_html=True)
    
    st.session_state.selected_amount = st.slider(
        "Select amount",
        min_value=100,
        max_value=user_data['buffer_limit'],
        value=st.session_state.selected_amount,
        step=50,
        label_visibility="collapsed"
    )
    
    st.markdown("**Quick select:**")
    cols = st.columns(4)
    amounts = [int(user_data['debit_order_amount']), 1000, 1500, 2000]
    labels = ["Debit order", "R1,000", "R1,500", "R2,000"]
    
    for i, (col, amount, label) in enumerate(zip(cols, amounts, labels)):
        with col:
            if st.button(f"R{amount}\n{label if i == 0 else ''}", key=f"quick_{amount}", use_container_width=True):
                st.session_state.selected_amount = amount
                st.rerun()
    
    st.markdown(f"""
    <div class="fnb-card" style="text-align: center; background: #F0FFF4;">
        <p class="grey-text" style="margin: 0 0 5px 0;">Next expected inflow</p>
        <p class="green-text" style="margin: 0; font-size: 22px;">R{user_data['predicted_inflow']:,}</p>
        <p class="compact" style="margin: 5px 0 0 0;">{user_data['inflow_date'].strftime('%d %B %Y')}</p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Continue", key="continue1", use_container_width=True):
        st.session_state.page = 2
        st.markdown("""
        <script>
        setTimeout(function() {
            window.scrollTo({top: 0, behavior: 'instant'});
            window.parent.document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
            document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
        }, 50);
        </script>
        """, unsafe_allow_html=True)
        st.rerun()
    
    if st.button("← Back", key="back1"):
        st.session_state.page = 0
        st.session_state.message_check_count = 0  # Reset counter
        st.rerun()
    
    show_bottom_nav(active="messages")

# Page 2: Expected Inflow Date
def show_page_2():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(2, 4)
    
    st.markdown('<p class="centered-header">Expected inflow date?</p>', unsafe_allow_html=True)
    st.markdown('<p style="text-align: center; color: #333333; font-weight: 600; margin: 10px 0;">Bridging amount: R{:,}</p>'.format(st.session_state.selected_amount), unsafe_allow_html=True)
    st.markdown('<p class="grey-text" style="text-align: center; margin: 5px 0 20px 0;">Select when you expect to receive funds - this affects your interest cost</p>', unsafe_allow_html=True)
    
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
                    <span class="grey-text">{st.session_state.selected_days} days (compound):</span>
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
                    <span class="grey-text">Interest (Compound, Standard OD):</span>
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
            <p class="red-text compact" style="margin: 10px 0 0 0;">At {cost_details['rate']:.2f}% p.a. (Standard overdraft, compounded daily)</p>
        </div>
        """, unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Compare scenarios</p>', unsafe_allow_html=True)
    
    comparison_html = '<div class="fnb-card"><div class="cost-table">'
    
    scenarios_to_compare = [3, 7, 14, 30]
    for idx, days in enumerate(scenarios_to_compare):
        scenario = calculate_full_cost(st.session_state.selected_amount, days)
        is_selected = days == st.session_state.selected_days
        is_escalated = scenario['scenario'] == 'escalated'
        
        label = f"→ {days} days" if is_selected else f"{days} days"
        if is_escalated:
            label += " (Escalated)"
        
        if is_escalated:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #666666; {"font-weight: 600;" if is_selected else ""}">{label}</span><span style="color: #E31E24; font-weight: 600;">R{scenario["total"]:.2f}</span></div>'
        elif is_selected:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #333333; font-weight: 600;">{label}</span><span style="color: #007c7f; font-weight: 600;">R{scenario["total"]:.2f}</span></div>'
        else:
            comparison_html += f'<div class="cost-row" style="border-bottom: 1px solid #F0F0F0;"><span style="color: #666666;">{label}</span><span style="color: #666666;">R{scenario["total"]:.2f}</span></div>'
    
    comparison_html += '</div><p class="compact" style="margin: 10px 0 0 0;">Escalated = Standard overdraft with activation fee. Interest compounded daily.</p></div>'
    st.markdown(comparison_html, unsafe_allow_html=True)
    
    days_until = (user_data['inflow_date'] - current_date).days
    st.markdown(f"""
    <div class="info-card">
        <p class="teal-text" style="margin: 0 0 5px 0; font-size: 15px;">Next predicted inflow: {user_data['inflow_date'].strftime('%d %B')}</p>
        <p class="grey-text" style="margin: 0;">in {days_until} days • We'll auto-repay from this</p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Continue", key="continue2", use_container_width=True):
        st.session_state.page = 3
        st.markdown("""
        <script>
        setTimeout(function() {
            window.scrollTo({top: 0, behavior: 'instant'});
            window.parent.document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
            document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
        }, 50);
        </script>
        """, unsafe_allow_html=True)
        st.rerun()
    
    if st.button("← Back", key="back2"):
        st.session_state.page = 1
        st.rerun()
    
    show_bottom_nav(active="messages")

# Page 3: What if things go wrong?
def show_page_3():
    st.markdown("""
    <div class="fnb-header">
        <h1>BufferShield</h1>
        <p>Predictive Overdraft</p>
    </div>
    """, unsafe_allow_html=True)
    
    show_progress_dots(3, 4)
    
    st.markdown('<p class="centered-header">What if things go wrong?</p>', unsafe_allow_html=True)
    st.markdown('<p class="grey-text" style="text-align: center; margin: 5px 0 20px 0;">We\'ve got you covered with transparent processes</p>', unsafe_allow_html=True)
    
    st.markdown('<p class="teal-heading">Grace Period</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">If your predicted inflow doesn't arrive on time, you get an automatic 3-day grace period with no additional fees. We understand that salary dates can shift.</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="teal-heading">Escalation to Standard Overdraft</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="fnb-card">
        <p class="grey-text" style="margin: 0; line-height: 1.6;">After the grace period, if still unpaid, BufferShield converts to a standard overdraft facility at {user_data['standard_rate']}% p.a. (compounded daily). No surprise fees—you'll know exactly what changes.</p>
    </div>
    """, unsafe_allow_html=True)
    
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
    
    st.markdown('<p class="teal-heading">Fee Transparency</p>', unsafe_allow_html=True)
    st.markdown(f"""
    <div class="info-card">
        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
            <span class="grey-text">Current BufferShield rate:</span>
            <span style="color: #333333; font-weight: 600;">{user_data['interest_rate']}% p.a.</span>
        </div>
        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
            <span class="grey-text">Standard overdraft rate:</span>
            <span style="color: #333333; font-weight: 600;">{user_data['standard_rate']}% p.a.</span>
        </div>
        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
            <span class="grey-text">Interest compounding:</span>
            <span style="color: #333333; font-weight: 600;">Daily</span>
        </div>
        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
            <span class="grey-text">Activation fee:</span>
            <span style="color: #333333; font-weight: 600;">R0.00</span>
        </div>
        <div style="display: flex; justify-content: space-between; margin-bottom: 15px;">
            <span class="grey-text">Monthly fee:</span>
            <span style="color: #333333; font-weight: 600;">R0.00</span>
        </div>
        <p style="margin: 0; padding-top: 12px; border-top: 1px solid #D0E8F0; color: #333333; font-weight: 600; text-align: center;">No hidden costs. Ever.</p>
    </div>
    """, unsafe_allow_html=True)
    
    if st.button("Review & Confirm", key="continue3", use_container_width=True):
        st.session_state.page = 4
        st.markdown("""
        <script>
        setTimeout(function() {
            window.scrollTo({top: 0, behavior: 'instant'});
            window.parent.document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
            document.querySelector('section.main').scrollTo({top: 0, behavior: 'instant'});
        }, 50);
        </script>
        """, unsafe_allow_html=True)
        st.rerun()
    
    if st.button("← Back", key="back3"):
        st.session_state.page = 2
        st.rerun()
    
    show_bottom_nav(active="messages")

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
    
    st.markdown(f"""
    <div class="fnb-card" style="background: #F5F5F5; text-align: center; padding: 30px 20px; border-left: 3px solid #007c7f;">
        <p style="color: #666666; margin: 0 0 10px 0; font-size: 14px;">Bridging amount</p>
        <h1 style="color: #333333; margin: 10px 0 20px 0; font-size: 42px; font-weight: 700;">R{st.session_state.selected_amount:,}</h1>
        <div style="height: 2px; background: #007c7f; margin: 20px auto; width: 80px;"></div>
        <p style="color: #666666; margin: 10px 0 0 0; font-size: 15px;">Expected repay: <strong style="color: #333333;">{st.session_state.selected_days} days</strong></p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="section-header">Total cost breakdown</p>', unsafe_allow_html=True)
    
    cost_details = calculate_full_cost(st.session_state.selected_amount, st.session_state.selected_days)
    
    cost_html = '<div class="fnb-card"><div class="cost-table">'
    
    if cost_details['scenario'] == 'on_time':
        items = [
            ("Bridging amount", f"R{st.session_state.selected_amount:,.2f}", False),
            ("Interest charge (compound)", f"R{cost_details['interest']:.2f}", False),
            ("Rate", f"{cost_details['rate']:.2f}% p.a. (BufferShield)", False),
            ("Activation fee", "R0.00", False),
            ("Monthly fee", "R0.00", False)
        ]
        if cost_details['grace_used'] > 0:
            items.insert(3, ("Grace period used", f"{cost_details['grace_used']} day(s)", False))
    else:
        items = [
            ("Bridging amount", f"R{st.session_state.selected_amount:,.2f}", False),
            ("Interest charge (compound)", f"R{cost_details['interest']:.2f}", True),
            ("Rate", f"{cost_details['rate']:.2f}% p.a. (Standard OD)", True),
            ("Activation fee", f"R{cost_details['activation_fee']:.2f}", True),
            ("Grace period exceeded", f"by {cost_details['days_beyond_grace']} day(s)", True)
        ]
    
    for i, (label, value, is_warning) in enumerate(items):
        color = "#E31E24" if is_warning else "#666666"
        value_color = "#E31E24" if is_warning else "#333333"
        border = 'border-bottom: 1px solid #F0F0F0;' if i < len(items) else ''
        cost_html += f'<div class="cost-row" style="{border}"><span style="color: {color};">{label}</span><span style="font-weight: 600; color: {value_color};">{value}</span></div>'
    
    total_color = "#E31E24" if cost_details['scenario'] == 'escalated' else "#333333"
    cost_html += f'<div class="cost-row" style="border-top: 2px solid #333333; border-bottom: none; margin-top: 10px; padding-top: 12px;"><span style="font-weight: 600; color: #333333;">Total repayment</span><span style="font-weight: 700; color: {total_color}; font-size: 18px;">R{cost_details["total"]:.2f}</span></div>'
    
    cost_html += '</div>'
    
    if cost_details['scenario'] == 'escalated':
        cost_html += f'<p class="red-text compact" style="margin: 12px 0 0 0;">⚠️ Escalates to standard overdraft on {cost_details["escalation_date"].strftime("%d %b")}</p>'
    
    cost_html += '</div>'
    
    st.markdown(cost_html, unsafe_allow_html=True)
    
    st.markdown(f"""
    <div class="info-card">
        <p class="teal-text" style="margin: 0 0 12px 0; font-size: 15px;">Auto-Repay</p>
        <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
            <span class="grey-text">Date:</span>
            <span style="color: #333333; font-weight: 600;">{user_data['inflow_date'].strftime('%d %B %Y')}</span>
        </div>
        <div style="display: flex; justify-content: space-between;">
            <span class="grey-text">Amount:</span>
            <span style="color: #333333; font-weight: 600;">R{cost_details['total']:.2f}</span>
        </div>
        <p class="compact" style="margin: 10px 0 0 0; color: #007c7f;">Deducted from predicted inflow</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown('<p class="compact" style="text-align: center; margin-bottom: 20px;">Funds available immediately after confirmation.</p>', unsafe_allow_html=True)
    
    # Terms and Conditions Checkbox
    terms_accepted = st.checkbox(
        "I accept the BufferShield Terms and Conditions",
        key="terms_checkbox",
        value=st.session_state.terms_accepted,
        help="You must accept the terms and conditions to activate BufferShield"
    )
    
    st.session_state.terms_accepted = terms_accepted
    
    col1, col2 = st.columns(2)
    
    with col1:
        if st.button("✓ Activate BufferShield", key="activate", type="primary", use_container_width=True, disabled=not terms_accepted):
            if not terms_accepted:
                st.warning("⚠️ Please accept the Terms and Conditions to proceed")
            elif user_data['activations_used'] >= user_data['activations_limit']:
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
            st.info("Offer declined. You can access BufferShield anytime from Messages.")
            st.session_state.page = 0
            st.session_state.message_check_count = 0
            st.rerun()
    
    if st.button("← Back", key="back4"):
        st.session_state.page = 3
        st.rerun()
    
    show_bottom_nav(active="messages")

# Main app routing
if st.session_state.page == 0:
    show_message_screen()
elif st.session_state.page == 1:
    show_page_1()
elif st.session_state.page == 2:
    show_page_2()
elif st.session_state.page == 3:
    show_page_3()
elif st.session_state.page == 4:
    show_page_4()
