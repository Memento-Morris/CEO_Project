import streamlit as st
import datetime
import math

# Page config
st.set_page_config(
    page_title="FNB PaySure",
    page_icon="💳",
    layout="centered",
    initial_sidebar_state="collapsed"
)

# ── Color Palette ─────────────────────────────────────────────────────────────
TEAL        = "#54B9AC"
LIGHT_TEAL  = "#76FAE9"
ORANGE      = "#E66C37"
BLACK       = "#333333"
WHITE       = "#FFFFFF"

# ── Custom CSS ────────────────────────────────────────────────────────────────
st.markdown(f"""
<style>
/* RCI tier pill */
.rci-pill {{
    display: inline-flex; align-items: center; gap: 8px;
    padding: 6px 14px; border-radius: 999px;
    font-weight: 700; font-size: 14px; margin-bottom: 4px;
}}
/* Event-type badge */
.event-badge {{
    display: inline-flex; align-items: center; gap: 6px;
    background: #f0fafb; border: 1px solid {TEAL};
    color: {BLACK}; padding: 5px 12px; border-radius: 8px;
    font-size: 12px; font-weight: 600;
}}
/* Guardrail bar */
.guardrail-bar {{
    background: #fff3ee; border-left: 4px solid {ORANGE};
    padding: 8px 12px; border-radius: 4px; font-size: 12px;
    color: {BLACK}; margin-bottom: 6px;
}}
/* Option card */
.option-card {{
    border: 1.5px solid #e2e8f0; border-radius: 12px;
    padding: 14px 16px; margin-bottom: 10px;
    background: {WHITE};
}}
.option-card.recommended {{
    border-color: {TEAL}; background: #f0fafb;
}}
.ralc-chip {{
    background: #e6faf8; color: {TEAL};
    font-size: 11px; font-weight: 600;
    padding: 2px 8px; border-radius: 999px;
    display: inline-block;
}}
/* Repayment window badge */
.repay-window {{
    background: {BLACK}; color: {WHITE};
    padding: 10px 18px; border-radius: 10px;
    text-align: center;
}}
</style>
""", unsafe_allow_html=True)

# ── Session state ─────────────────────────────────────────────────────────────
for k, v in [('page', 0), ('shortfall_amount', 800), ('expected_repay_days', 7),
             ('unread_count', 1), ('protection_activated', False)]:
    if k not in st.session_state:
        st.session_state[k] = v

# ── User / account data ───────────────────────────────────────────────────────
current_date = datetime.date.today()

user_data = {
    "name": "John Doe",
    "account_number": "****7823",
    "current_balance": 450.00,
    "inflow_date": current_date + datetime.timedelta(days=7),
    "predicted_inflow": 18500,
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
    # Shortfall history (for guardrails)
    "shortfall_events_this_quarter": 2,
    "max_shortfall_events_threshold": 3,
    # Credit facilities
    "overdraft_limit": 2000,
    "overdraft_rate": 18.25,
    "overdraft_monthly_fee": 69.00,
    "temp_loan_rate": 19.75,
    "temp_loan_max": 5000,
    "credit_card_rate": 22.00,
    "credit_card_limit": 3000,
    "salary_advance_rate": 15.00,
    "salary_advance_max": 2000,
}

# ── Backend logic ─────────────────────────────────────────────────────────────

def calculate_credit_cost(amount, days, rate):
    daily_rate = rate / 100 / 365
    total = amount * math.pow(1 + daily_rate, days)
    interest = total - amount
    return {'interest': round(interest, 2), 'total': round(total, 2)}

def calculate_rci(ud, days=0):
    weights = {'income_stability': 0.30, 'debit_success': 0.25,
               'overdraft_discipline': 0.20, 'savings_buffer': 0.15,
               'credit_performance': 0.10}
    overdraft_score = 1 - ud['overdraft_utilization']
    base_rci = (
        ud['income_stability_score']       * weights['income_stability'] +
        ud['debit_success_ratio']          * weights['debit_success'] +
        overdraft_score                    * weights['overdraft_discipline'] +
        ud['savings_buffer_ratio']         * weights['savings_buffer'] +
        ud['credit_repayment_performance'] * weights['credit_performance']
    )
    if days > 0:
        time_penalty = min(days * 0.005, 0.20)
        base_rci -= time_penalty
    return round(max(base_rci, 0.30), 2)

def get_rci_tier(rci):
    if rci >= 0.85:
        return 1, "Excellent", TEAL,   "#f0fafb"
    elif rci >= 0.70:
        return 2, "Good",      TEAL,   "#f0fafb"
    elif rci >= 0.55:
        return 3, "Fair",      ORANGE, "#fff3ee"
    else:
        return 4, "Low",       ORANGE, "#fff3ee"

def classify_event(shortfall, days, balance):
    if days <= 3:
        return "Payment Orchestration Risk", "Timing mismatch — funds arriving imminently"
    elif balance > 0 and shortfall / balance < 3:
        return "Short-Duration Liquidity Risk", "Genuine gap — balance insufficient for committed outflow"
    else:
        return "Extended Liquidity Deficit", "Structural shortfall — income insufficient to cover obligations"

def calculate_ralc(amount, days, rate, rci):
    cost = calculate_credit_cost(amount, days, rate)
    ralc = cost['interest'] / rci if rci > 0 else cost['interest']
    return round(ralc, 2)

def get_credit_options(shortfall, days, ud, rci_tier, rci_score):
    options = []

    # 1. Overdraft
    if shortfall <= ud['overdraft_limit']:
        c = calculate_credit_cost(shortfall, days, ud['overdraft_rate'])
        fee = ud['overdraft_monthly_fee'] if shortfall >= 200 else 0
        ralc = calculate_ralc(shortfall, days, ud['overdraft_rate'], rci_score)
        options.append({
            'name': 'Overdraft',
            'amount': shortfall, 'days': days,
            'rate': ud['overdraft_rate'],
            'interest': c['interest'], 'total': c['total'],
            'fees': fee, 'grand_total': c['total'] + fee,
            'ralc': ralc,
            'optimal_for': 'Very short gaps (1–3 days)',
            'why_chosen': f"Lowest cost for your {days}-day window with no new credit application required.",
        })

    # 2. Temporary Loan
    if shortfall <= ud['temp_loan_max'] and rci_tier <= 3:
        c = calculate_credit_cost(shortfall, days, ud['temp_loan_rate'])
        init_fee = max(50, shortfall * 0.02)
        ralc = calculate_ralc(shortfall, days, ud['temp_loan_rate'], rci_score)
        options.append({
            'name': 'Temporary Loan',
            'amount': shortfall, 'days': days,
            'rate': ud['temp_loan_rate'],
            'interest': c['interest'], 'total': c['total'],
            'fees': init_fee, 'grand_total': c['total'] + init_fee,
            'ralc': ralc,
            'optimal_for': 'Longer gaps (30+ days)',
            'why_chosen': f"Fixed repayment gives certainty; preferred when gap exceeds 10 days.",
        })

    # 3. Credit Card Cash Advance
    if shortfall <= ud['credit_card_limit'] and rci_tier <= 2:
        c = calculate_credit_cost(shortfall, days, ud['credit_card_rate'])
        fee = round(shortfall * 0.015, 2)
        ralc = calculate_ralc(shortfall, days, ud['credit_card_rate'], rci_score)
        options.append({
            'name': 'Credit Card Advance',
            'amount': shortfall, 'days': days,
            'rate': ud['credit_card_rate'],
            'interest': c['interest'], 'total': c['total'],
            'fees': fee, 'grand_total': c['total'] + fee,
            'ralc': ralc,
            'optimal_for': 'Tier 1–2 customers, short gaps',
            'why_chosen': "Available due to strong credit history; cost is higher — consider only if overdraft unavailable.",
        })

    # 4. Salary Advance
    if shortfall <= ud['salary_advance_max'] and rci_tier <= 3:
        c = calculate_credit_cost(shortfall, days, ud['salary_advance_rate'])
        ralc = calculate_ralc(shortfall, days, ud['salary_advance_rate'], rci_score)
        options.append({
            'name': 'Salary Advance',
            'amount': shortfall, 'days': days,
            'rate': ud['salary_advance_rate'],
            'interest': c['interest'], 'total': c['total'],
            'fees': 0, 'grand_total': c['total'],
            'ralc': ralc,
            'optimal_for': 'Confirmed salary inflow ≤14 days',
            'why_chosen': "Lowest rate available; repaid directly against confirmed salary inflow.",
        })

    return options

def get_recommended_option(options, days, rci_tier):
    if not options:
        return None
    if days <= 10:
        od = [o for o in options if 'Overdraft' in o['name']]
        if od:
            return od[0]
    if days > 30 or rci_tier >= 3:
        tl = [o for o in options if 'Temporary Loan' in o['name']]
        if tl:
            return tl[0]
    return min(options, key=lambda x: x['grand_total'])


# ── RCI Widget (reusable) ─────────────────────────────────────────────────────

def render_rci_widget(rci_score, rci_tier, rci_label, rci_color, rci_bg):
    st.markdown("**Repayment Certainty Index (RCI)**")
    tier_config = [
        (1, "Excellent", TEAL,   "#f0fafb"),
        (2, "Good",      TEAL,   "#f0fafb"),
        (3, "Fair",      ORANGE, "#fff3ee"),
        (4, "Low",       ORANGE, "#fff3ee"),
    ]
    cols = st.columns(4)
    for i, (num, label, col, bg) in enumerate(tier_config):
        with cols[i]:
            is_active = (num == rci_tier)
            border = f"2px solid {col}" if is_active else "1.5px solid #e2e8f0"
            opacity = "1" if is_active else "0.4"
            st.markdown(
                f"""<div style="background:{bg if is_active else WHITE};
                    border:{border}; border-radius:8px; padding:8px 4px;
                    text-align:center; opacity:{opacity};">
                    <div style="font-size:11px;font-weight:700;color:{col};">TIER {num}</div>
                    <div style="font-size:10px;color:#555;">{label}</div>
                </div>""",
                unsafe_allow_html=True
            )

    st.markdown(
        f"""<div style="margin-top:10px;background:{rci_bg};
            border-left:4px solid {rci_color};
            padding:8px 12px;border-radius:6px;">
            <span style="font-size:22px;font-weight:800;color:{rci_color};">{rci_score}</span>
            <span style="font-size:13px;color:#555;margin-left:8px;">/ 1.00 — {rci_label}</span>
        </div>""",
        unsafe_allow_html=True
    )

    with st.expander("How your RCI is calculated"):
        factors = {
            "Income Stability":      (user_data['income_stability_score'],       0.30),
            "Payment History":       (user_data['debit_success_ratio'],           0.25),
            "Overdraft Discipline":  (1 - user_data['overdraft_utilization'],     0.20),
            "Savings Buffer":        (user_data['savings_buffer_ratio'],          0.15),
            "Credit Performance":    (user_data['credit_repayment_performance'],  0.10),
        }
        for label, (score, weight) in factors.items():
            col1, col2 = st.columns([3, 1])
            with col1:
                st.markdown(f"<div style='font-size:12px;'>{label} <span style='color:#888;'>(weight {int(weight*100)}%)</span></div>",
                            unsafe_allow_html=True)
                st.progress(score)
            with col2:
                st.markdown(f"<div style='font-size:13px;font-weight:600;padding-top:20px;'>{int(score*100)}%</div>",
                            unsafe_allow_html=True)


# ── Guardrails widget ─────────────────────────────────────────────────────────

def render_guardrails():
    events = user_data['shortfall_events_this_quarter']
    threshold = user_data['max_shortfall_events_threshold']
    pct = events / threshold
    label = "Approaching limit" if pct >= 0.66 else "Within normal range"
    st.markdown(
        f"""<div class="guardrail-bar">
            <strong>Guardrails Active</strong> &nbsp;|&nbsp;
            Shortfall events this quarter: <strong>{events}/{threshold}</strong>
            &nbsp;—&nbsp; {label}
        </div>""",
        unsafe_allow_html=True
    )


# ── PAGE 0 — Messages ─────────────────────────────────────────────────────────

def show_message_screen():
    st.markdown("### Messages")
    st.caption("Important updates for you")
    st.divider()

    st.markdown("#### Today")
    with st.container():
        st.error("**Payment Protection Available**")
        st.write(
            f"**{user_data['debit_order_recipient']}** payment of "
            f"R{user_data['debit_order_amount']:,.2f} on "
            f"{user_data['debit_order_date'].strftime('%d %b')}"
        )
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


# ── PAGE 1 — Protection screen ────────────────────────────────────────────────

def show_protection_screen():
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(shortfall, days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, days, rci_tier)

    # ── Event classification ──
    event_type, event_desc = classify_event(shortfall, days, user_data['current_balance'])
    st.markdown(
        f"""<div class="event-badge">
            <span>{event_type}</span>
        </div>
        <div style="font-size:12px;color:#555;margin:4px 0 12px 0;">{event_desc}</div>""",
        unsafe_allow_html=True
    )

    st.markdown("## We'll protect your payment")

    # ── RCI Widget ──
    render_rci_widget(rci_score, rci_tier, rci_label, rci_color, rci_bg)
    st.markdown("")

    # ── Guardrails ──
    render_guardrails()
    st.markdown("")

    # ── Summary card ──
    col_a, col_b, col_c = st.columns(3)
    with col_a:
        st.markdown("**Payment**")
        st.markdown(f"### {user_data['debit_order_recipient']}")
    with col_b:
        st.markdown("**Amount Covered**")
        st.markdown(f"### R{int(shortfall):,}")
    with col_c:
        st.markdown(
            f"""<div class="repay-window">
                <div style="font-size:10px;font-weight:600;letter-spacing:1px;opacity:.7;">REPAYMENT WINDOW</div>
                <div style="font-size:26px;font-weight:800;">{days} days</div>
                <div style="font-size:11px;opacity:.8;">{user_data['inflow_date'].strftime('%d %B')}</div>
            </div>""",
            unsafe_allow_html=True
        )

    st.markdown("---")

    # ── Recommended option highlight ──
    if recommended:
        cost = recommended['grand_total'] - shortfall
        st.markdown(f"**Total Cost of Liquidity** &nbsp; <span style='color:#888;font-size:12px;'>via {recommended['name']}</span>",
                    unsafe_allow_html=True)
        col1, col2 = st.columns([1, 2])
        with col1:
            st.markdown(f"<span style='font-size:36px;font-weight:800;color:{TEAL};'>R{cost:.2f}</span>",
                        unsafe_allow_html=True)
            st.markdown(
                f"<span class='ralc-chip' title='Risk-Adjusted Liquidity Cost: raw cost scaled by your RCI'>RALC R{recommended['ralc']:.2f}</span>",
                unsafe_allow_html=True
            )
        with col2:
            st.info(f"**Why this option?** {recommended['why_chosen']}")

    st.markdown("")
    if st.button("Protect my payment", use_container_width=True, type="primary", key="protect_btn"):
        st.session_state.protection_activated = True
        st.session_state.page = 2
        st.rerun()
    if st.button("Compare all options", use_container_width=True, key="options_link"):
        st.session_state.page = 3
        st.rerun()
    if st.button("Back to Messages", use_container_width=True, key="back_msg"):
        st.session_state.page = 0
        st.rerun()


# ── PAGE 2 — Confirmation ─────────────────────────────────────────────────────

def show_confirmation_screen():
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(shortfall, days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, days, rci_tier)

    st.balloons()
    st.markdown("# Your payment is secured")

    with st.container():
        st.success(f"""
**{user_data['debit_order_recipient']}** payment will go through on {user_data['debit_order_date'].strftime('%d %B')}.

**Automatic repayment scheduled:**
- Amount: R{recommended['grand_total']:.2f}
- Date: {user_data['inflow_date'].strftime('%d %B %Y')}
- Source: Next salary deposit
- Total Cost of Liquidity: R{recommended['grand_total'] - shortfall:.2f}

You're all set. Nothing more to do.
        """)

    if st.button("Done", use_container_width=True, type="primary"):
        st.session_state.page = 0
        st.rerun()
    if st.button("View details", use_container_width=True, key="view_details"):
        st.session_state.page = 3
        st.rerun()


# ── PAGE 3 — Compare options ──────────────────────────────────────────────────

def show_options_screen():
    st.markdown("### Compare Options")
    st.caption("All eligible facilities · All costs shown")
    st.divider()

    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(shortfall, days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, days, rci_tier)

    st.markdown(
        f"""<div style="background:{rci_bg};border-left:4px solid {rci_color};
            padding:8px 12px;border-radius:6px;margin-bottom:12px;">
            <strong>Your RCI:</strong>
            <span style="font-size:18px;font-weight:800;color:{rci_color};margin:0 6px;">{rci_score}</span>
            Tier {rci_tier} — {rci_label}
            &nbsp;|&nbsp;
            <span style="font-size:12px;color:#555;">{days}-day repayment window</span>
        </div>""",
        unsafe_allow_html=True
    )

    render_guardrails()
    st.markdown("")

    # Option cards
    for opt in options:
        is_rec = recommended and opt['name'] == recommended['name']
        card_class = "option-card recommended" if is_rec else "option-card"
        rec_badge = " — Recommended" if is_rec else ""

        st.markdown(f"<div class='{card_class}'>", unsafe_allow_html=True)

        col_title, col_total = st.columns([3, 1])
        with col_title:
            st.markdown(f"**{opt['name']}**{rec_badge} &nbsp; `{opt['rate']}% p.a.`")
        with col_total:
            st.markdown(f"<div style='text-align:right;font-size:18px;font-weight:800;color:{BLACK};'>R{opt['grand_total']:.2f}</div>",
                        unsafe_allow_html=True)

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Amount", f"R{opt['amount']:,.2f}")
        c2.metric(f"Interest ({opt['days']}d)", f"R{opt['interest']:.2f}")
        c3.metric("Fees", f"R{opt['fees']:.2f}")
        c4.metric("RALC", f"R{opt['ralc']:.2f}", help="Risk-Adjusted Liquidity Cost: raw interest cost / your RCI score. Lower = better value for your risk profile.")

        st.markdown(f"<div style='margin-top:8px;font-size:12px;color:#555;'>{opt['why_chosen']}</div>",
                    unsafe_allow_html=True)
        st.markdown(f"<div style='font-size:11px;color:#888;margin-top:4px;'>Best for: {opt['optimal_for']}</div>",
                    unsafe_allow_html=True)
        st.markdown("</div>", unsafe_allow_html=True)
        st.markdown("")

    if st.button("Back", use_container_width=True):
        st.session_state.page = 1
        st.rerun()


# ── PAGE 4 — Calculator ───────────────────────────────────────────────────────

def show_calculator_screen():
    st.markdown("### Cost Calculator")
    st.caption("Explore different amounts and repayment windows")
    st.divider()

    col1, col2 = st.columns(2)
    with col1:
        st.markdown("**Amount (R)**")
        calc_amount = st.slider("Amount", 100, 5000,
                                int(st.session_state.shortfall_amount),
                                step=50, label_visibility="collapsed")
        st.metric("You'll borrow", f"R{calc_amount:,}")
    with col2:
        st.markdown("**Repayment window (days)**")
        calc_days = st.slider("Days", 1, 60,
                              st.session_state.expected_repay_days,
                              step=1, label_visibility="collapsed")
        st.metric("Repay in", f"{calc_days} days")

    rci_score = calculate_rci(user_data, days=calc_days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(calc_amount, calc_days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, calc_days, rci_tier)

    st.divider()

    st.markdown(
        f"""<div style="background:{rci_bg};border-left:4px solid {rci_color};
            padding:8px 12px;border-radius:6px;margin-bottom:12px;">
            <strong>RCI at {calc_days}-day horizon:</strong>
            <span style="font-size:18px;font-weight:800;color:{rci_color};margin:0 6px;">{rci_score}</span>
            Tier {rci_tier} — {rci_label}
        </div>""",
        unsafe_allow_html=True
    )

    event_type, event_desc = classify_event(calc_amount, calc_days, user_data['current_balance'])
    st.markdown(
        f"""<div class="event-badge">{event_type}</div>
        <div style="font-size:12px;color:#555;margin:4px 0 12px 0;">{event_desc}</div>""",
        unsafe_allow_html=True
    )

    if not options:
        st.warning("No eligible facilities for this combination.")
    else:
        for opt in options:
            is_rec = recommended and opt['name'] == recommended['name']
            label = f"{opt['name']} — Recommended" if is_rec else opt['name']

            if is_rec:
                st.success(f"**{label}**")
            else:
                st.info(f"**{label}**")

            c1, c2, c3 = st.columns(3)
            c1.metric("Total Cost of Liquidity", f"R{opt['grand_total'] - opt['amount']:.2f}")
            c2.metric("Total to Repay", f"R{opt['grand_total']:,.2f}")
            c3.metric("RALC", f"R{opt['ralc']:.2f}",
                      help="Risk-Adjusted Liquidity Cost")
            st.caption(f"Rate {opt['rate']}% p.a. · Best for: {opt['optimal_for']}")
            st.divider()

    if st.button("Back to Messages", use_container_width=True):
        st.session_state.page = 0
        st.rerun()


# ── Router ────────────────────────────────────────────────────────────────────

pages = {
    0: show_message_screen,
    1: show_protection_screen,
    2: show_confirmation_screen,
    3: show_options_screen,
    4: show_calculator_screen,
}

pages[st.session_state.page]()

st.markdown("---")
nav_cols = st.columns(4)
nav_items = [
    (0, "Messages"),
    (1, "Protect"),
    (3, "Options"),
    (4, "Calculator"),
]
for col, (p, label) in zip(nav_cols, nav_items):
    with col:
        is_active = st.session_state.page == p
        color = TEAL if is_active else BLACK
        weight = "700" if is_active else "400"
        st.markdown(
            f"<div style='text-align:center;font-size:13px;font-weight:{weight};color:{color};'>{label}</div>",
            unsafe_allow_html=True
        )
        if st.button(label, key=f"nav_{p}", use_container_width=True, label_visibility="collapsed"):
            st.session_state.page = p
            st.rerun()
