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

# ── Custom CSS ────────────────────────────────────────────────────────────────
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=DM+Mono:wght@500&display=swap');

* { font-family: 'DM Sans', sans-serif; }

/* ── Step cards ── */
.step-card {
    border-radius: 16px;
    padding: 20px 22px;
    margin-bottom: 16px;
    border: 1.5px solid #e2e8f0;
    background: #ffffff;
}
.step-label {
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    color: #94a3b8;
    margin-bottom: 10px;
}
/* Step 1 — Problem */
.step-problem {
    background: #0A1628;
    border: none;
    color: white;
}
.step-problem .step-label { color: #64748b; }
.problem-amount {
    font-size: 42px;
    font-weight: 700;
    color: #ffffff;
    line-height: 1;
    font-family: 'DM Mono', monospace;
}
.problem-meta {
    font-size: 14px;
    color: #94a3b8;
    margin-top: 6px;
}
.problem-highlight {
    color: #f97316;
    font-weight: 600;
}
/* Step 2 — Trust */
.step-trust {
    background: #f8fafc;
    border-color: #e2e8f0;
}
.rci-score-big {
    font-size: 38px;
    font-weight: 700;
    font-family: 'DM Mono', monospace;
    line-height: 1;
}
.rci-bar-track {
    background: #e2e8f0;
    border-radius: 999px;
    height: 8px;
    margin: 10px 0 6px 0;
    overflow: hidden;
}
.tier-row {
    display: flex;
    gap: 6px;
    margin-top: 10px;
}
.tier-chip {
    flex: 1;
    text-align: center;
    padding: 5px 4px;
    border-radius: 6px;
    font-size: 10px;
    font-weight: 700;
    border: 1.5px solid transparent;
}
/* Step 3 — Solution */
.step-solution {
    background: #f0fdf4;
    border-color: #86efac;
}
.cost-big {
    font-size: 42px;
    font-weight: 700;
    color: #16a34a;
    font-family: 'DM Mono', monospace;
    line-height: 1;
}
.solution-meta {
    font-size: 13px;
    color: #4b5563;
    margin-top: 6px;
}
/* CTA button override */
.stButton > button[kind="primary"] {
    background: #00A651 !important;
    border: none !important;
    border-radius: 12px !important;
    font-size: 16px !important;
    font-weight: 700 !important;
    padding: 14px !important;
    color: white !important;
    transition: opacity 0.15s;
}
.stButton > button[kind="primary"]:hover { opacity: 0.88; }

/* Secondary buttons */
.stButton > button:not([kind="primary"]) {
    border-radius: 10px !important;
    font-size: 13px !important;
    color: #374151 !important;
}

/* Guardrail strip */
.guardrail-strip {
    background: #fff8e1;
    border-left: 3px solid #f59e0b;
    padding: 8px 12px;
    border-radius: 6px;
    font-size: 12px;
    color: #92400e;
    margin: 4px 0 16px 0;
}

/* Option card for compare page */
.option-card {
    border: 1.5px solid #e2e8f0;
    border-radius: 12px;
    padding: 16px 18px;
    margin-bottom: 12px;
    background: white;
}
.option-card.recommended {
    border-color: #00A651;
    background: #f0fdf4;
}

/* Nav */
.nav-active { color: #00A651 !important; font-weight: 700 !important; }

/* Confirmation */
.confirm-hero {
    background: linear-gradient(135deg, #0A1628 0%, #1e3a5f 100%);
    border-radius: 20px;
    padding: 32px 24px;
    text-align: center;
    color: white;
    margin-bottom: 20px;
}
</style>
""", unsafe_allow_html=True)

# ── Session state ─────────────────────────────────────────────────────────────
for k, v in [('page', 0), ('shortfall_amount', 800), ('expected_repay_days', 7),
             ('unread_count', 1), ('protection_activated', False), ('selected_option', None)]:
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
    "income_stability_score": 0.78,
    "debit_success_ratio": 0.75,
    "overdraft_utilization": 0.48,
    "savings_buffer_ratio": 0.12,
    "credit_repayment_performance": 0.78,
    "shortfall_events_this_quarter": 2,
    "max_shortfall_events_threshold": 3,
    "overdraft_limit": 20000,
    "overdraft_rate": 18.25,
    "overdraft_monthly_fee": 69.00,
    "temp_loan_rate": 19.75,
    "temp_loan_max": 5000,
    "salary_advance_rate": 15.00,
    "salary_advance_max": 2000,
}

# ── Backend logic ─────────────────────────────────────────────────────────────

def calculate_behavioural_cost(amount, days, rate):
    """Engine 1 — Real cost for actual usage window (daily accrual)."""
    daily_rate = rate / 100 / 365
    interest = amount * daily_rate * days
    return {'interest': round(interest, 2), 'total': round(amount + interest, 2)}

def calculate_regulatory_cost(limit, annual_rate, monthly_fee, term_months=12):
    """Engine 2 — NCA disclosure view (full limit, amortised over 12 months)."""
    r = annual_rate / 100 / 12
    if r == 0:
        pmt = limit / term_months
    else:
        pmt = limit * (r / (1 - (1 + r) ** -term_months))
    total_repayment = round(pmt * term_months + monthly_fee * term_months, 2)
    total_interest = round(pmt * term_months - limit, 2)
    total_fees = round(monthly_fee * term_months, 2)
    return {
        'monthly_instalment': round(pmt, 2),
        'total_repayment': total_repayment,
        'total_interest': total_interest,
        'total_fees': total_fees,
        'term_months': term_months,
    }

def calculate_credit_cost(amount, days, rate):
    """Alias — behavioural engine used throughout."""
    return calculate_behavioural_cost(amount, days, rate)

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
        return 1, "Excellent", "#00A651", "#f0fdf4"
    elif rci >= 0.70:
        return 2, "Good",      "#007c7f", "#f0fafa"
    elif rci >= 0.55:
        return 3, "Fair",      "#FF9900", "#fffbeb"
    else:
        return 4, "Low",       "#E31E24", "#fef2f2"

def calculate_ralc(amount, days, rate, rci):
    cost = calculate_credit_cost(amount, days, rate)
    ralc = cost['interest'] / rci if rci > 0 else cost['interest']
    return round(ralc, 2)

def get_credit_options(shortfall, days, ud, rci_tier, rci_score):
    options = []
    if shortfall <= ud['overdraft_limit']:
        c = calculate_credit_cost(shortfall, days, ud['overdraft_rate'])
        fee = ud['overdraft_monthly_fee'] if shortfall >= 200 else 0
        options.append({
            'name': 'Overdraft', 'amount': shortfall, 'days': days,
            'rate': ud['overdraft_rate'], 'interest': c['interest'],
            'total': c['total'], 'fees': fee, 'grand_total': c['total'] + fee,
            'ralc': calculate_ralc(shortfall, days, ud['overdraft_rate'], rci_score),
            'note': f"No new credit application needed. Monthly service fee of R{ud['overdraft_monthly_fee']:.0f} applies regardless of how long you use it — most cost-effective when you need more than R{int(ud['overdraft_monthly_fee'] * 10):,} or carry the balance for 30+ days.",
        })
    if shortfall <= ud['temp_loan_max']:
        c = calculate_credit_cost(shortfall, days, ud['temp_loan_rate'])
        init_fee = max(50, shortfall * 0.02)
        options.append({
            'name': 'Temporary Loan', 'amount': shortfall, 'days': days,
            'rate': ud['temp_loan_rate'], 'interest': c['interest'],
            'total': c['total'], 'fees': init_fee, 'grand_total': c['total'] + init_fee,
            'ralc': calculate_ralc(shortfall, days, ud['temp_loan_rate'], rci_score),
            'note': f"Fixed initiation fee of R{max(50, shortfall * 0.02):.0f} makes this expensive for short gaps. Better suited to gaps of 30+ days where interest savings offset the fee.",
        })
    if shortfall <= ud['salary_advance_max']:
        c = calculate_credit_cost(shortfall, days, ud['salary_advance_rate'])
        options.append({
            'name': 'Salary Advance', 'amount': shortfall, 'days': days,
            'rate': ud['salary_advance_rate'], 'interest': c['interest'],
            'total': c['total'], 'fees': 0, 'grand_total': c['total'],
            'ralc': calculate_ralc(shortfall, days, ud['salary_advance_rate'], rci_score),
            'note': "Lowest rate available with no fees. Repaid directly from your confirmed salary deposit. Best choice when your shortfall is within the advance limit.",
        })
    options.sort(key=lambda x: x['grand_total'])
    return options

def get_recommended_option(options, days, rci_tier):
    if not options:
        return None
    return min(options, key=lambda x: x['grand_total'])


# ── PAGE 0 — Messages ─────────────────────────────────────────────────────────

def show_message_screen():
    st.markdown("### Messages")
    st.caption(f"Hi {user_data['name'].split()[0]} · {user_data['account_number']}")
    st.divider()

    st.markdown("#### Today")

    # Alert card
    st.markdown(f"""
    <div style="background:#fff4e5;border-left:4px solid #f97316;
        border-radius:12px;padding:16px 18px;margin-bottom:12px;">
        <div style="font-size:11px;font-weight:700;letter-spacing:1px;
            color:#ea580c;text-transform:uppercase;margin-bottom:6px;">
            Action Required
        </div>
        <div style="font-size:16px;font-weight:700;color:#1a1a2e;">
            {user_data['debit_order_recipient']} · R{user_data['debit_order_amount']:,.2f}
        </div>
        <div style="font-size:13px;color:#6b7280;margin-top:4px;">
            Due {user_data['debit_order_date'].strftime('%d %b')} · 
            <span style="color:#dc2626;font-weight:600;">
                R{user_data['predicted_shortfall']:,.0f} shortfall predicted
            </span>
        </div>
        <div style="font-size:12px;color:#6b7280;margin-top:6px;">
            FNB can cover this automatically — tap below to review.
        </div>
    </div>
    """, unsafe_allow_html=True)

    if st.button("Review Payment Protection →", use_container_width=True, type="primary"):
        st.session_state.unread_count = 0
        st.session_state.page = 1
        st.rerun()

    st.divider()
    st.markdown("#### Earlier")
    st.info("Cashflow Insight — R2,450 spent on groceries this month vs R2,100 last month")


# ── PAGE 1 — Protection screen (3-step narrative) ─────────────────────────────

def show_protection_screen():
    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(shortfall, days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, days, rci_tier)

    st.markdown("### Payment Protection")
    st.caption(f"{user_data['debit_order_date'].strftime('%d %B %Y')}")
    st.markdown("")

    # ── STEP 1: THE PROBLEM ──────────────────────────────────────────────────
    st.markdown("""<div class="step-label" style="color:#94a3b8;">STEP 1 — WHAT'S HAPPENING</div>""",
                unsafe_allow_html=True)
    st.markdown(f"""
    <div class="step-card step-problem">
        <div class="step-label">Upcoming payment</div>
        <div style="display:flex;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;gap:12px;">
            <div>
                <div style="font-size:13px;color:#94a3b8;margin-bottom:4px;">
                    {user_data['debit_order_recipient']} · due {user_data['debit_order_date'].strftime('%d %b')}
                </div>
                <div class="problem-amount">R{user_data['debit_order_amount']:,.0f}</div>
                <div class="problem-meta">
                    Your balance &nbsp;<span style="color:#64748b;">R{user_data['current_balance']:,.0f}</span>
                    &nbsp;·&nbsp;
                    Shortfall &nbsp;<span class="problem-highlight">R{shortfall:,.0f}</span>
                </div>
            </div>
            <div style="text-align:right;">
                <div style="font-size:11px;color:#64748b;margin-bottom:4px;">Salary arrives in</div>
                <div style="font-size:28px;font-weight:700;color:#ffffff;font-family:'DM Mono',monospace;">{days} days</div>
                <div style="font-size:12px;color:#64748b;">{user_data['inflow_date'].strftime('%d %B')}</div>
            </div>
        </div>
    </div>
    """, unsafe_allow_html=True)

    # ── STEP 2: TRUST SIGNAL ─────────────────────────────────────────────────
    st.markdown("""<div class="step-label" style="color:#94a3b8;margin-top:4px;">STEP 2 — YOUR CREDIT PROFILE</div>""",
                unsafe_allow_html=True)

    bar_width = int(rci_score * 100)
    tier_chips = ""
    for num, label, col, bg in [(1,"Excellent","#00A651","#f0fdf4"),(2,"Good","#007c7f","#f0fafa"),
                                  (3,"Fair","#FF9900","#fffbeb"),(4,"Low","#E31E24","#fef2f2")]:
        active = num == rci_tier
        border = f"2px solid {col}" if active else "1.5px solid #e2e8f0"
        opacity = "1" if active else "0.35"
        tier_chips += f"""<div class="tier-chip" style="border:{border};background:{bg if active else 'white'};
            color:{col};opacity:{opacity};">
            <div>T{num}</div><div style="font-weight:400;font-size:9px;">{label}</div>
        </div>"""

    st.markdown(f"""
    <div class="step-card step-trust">
        <div class="step-label">Repayment Certainty Index (RCI)</div>
        <div style="display:flex;align-items:center;gap:16px;">
            <div>
                <div class="rci-score-big" style="color:{rci_color};">{rci_score}</div>
                <div style="font-size:12px;color:#6b7280;">out of 1.00 &nbsp;·&nbsp; <strong>{rci_label}</strong></div>
            </div>
            <div style="flex:1;">
                <div class="rci-bar-track">
                    <div style="height:100%;width:{bar_width}%;background:{rci_color};border-radius:999px;"></div>
                </div>
                <div style="font-size:11px;color:#6b7280;">
                    Based on your income stability, payment history & overdraft discipline
                </div>
                <div class="tier-row">{tier_chips}</div>
            </div>
        </div>
    </div>
    """, unsafe_allow_html=True)

    with st.expander("See how your RCI is calculated"):
        factors = {
            "Income Stability":      (user_data['income_stability_score'],       0.30),
            "Payment History":       (user_data['debit_success_ratio'],           0.25),
            "Overdraft Discipline":  (1 - user_data['overdraft_utilization'],     0.20),
            "Savings Buffer":        (user_data['savings_buffer_ratio'],          0.15),
            "Credit Performance":    (user_data['credit_repayment_performance'],  0.10),
        }
        for label, (score, weight) in factors.items():
            c1, c2 = st.columns([3, 1])
            with c1:
                st.markdown(f"<div style='font-size:12px;'>{label} <span style='color:#888;'>(weight {int(weight*100)}%)</span></div>",
                            unsafe_allow_html=True)
                st.progress(score)
            with c2:
                st.markdown(f"<div style='font-size:13px;font-weight:600;padding-top:20px;'>{int(score*100)}%</div>",
                            unsafe_allow_html=True)

        events = user_data['shortfall_events_this_quarter']
        threshold = user_data['max_shortfall_events_threshold']
        st.markdown(f"""
        <div class="guardrail-strip">
            <strong>Guardrails:</strong> {events}/{threshold} shortfall events this quarter &nbsp;·&nbsp;
            {"⚠️ Approaching limit" if events/threshold >= 0.66 else "✅ Within normal range"}
        </div>
        """, unsafe_allow_html=True)

    # ── STEP 3: THE SOLUTION ─────────────────────────────────────────────────
    st.markdown("""<div class="step-label" style="color:#94a3b8;margin-top:4px;">STEP 3 — OUR RECOMMENDATION</div>""",
                unsafe_allow_html=True)

    if recommended:
        cost = recommended['grand_total'] - shortfall
        st.markdown(f"""
        <div class="step-card step-solution">
            <div class="step-label" style="color:#16a34a;">Best option for you</div>
            <div style="display:flex;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;gap:12px;">
                <div>
                    <div style="font-size:13px;color:#4b5563;margin-bottom:4px;">
                        {recommended['name']} &nbsp;·&nbsp; {recommended['rate']}% p.a.
                    </div>
                    <div class="cost-big">R{cost:.2f}</div>
                    <div class="solution-meta">
                        Total to repay &nbsp;<strong>R{recommended['grand_total']:,.2f}</strong>
                        &nbsp;·&nbsp; on {user_data['inflow_date'].strftime('%d %B')}
                    </div>
                    <div style="font-size:12px;color:#6b7280;margin-top:6px;">
                        Repaid automatically from your salary deposit
                    </div>
                </div>
                <div style="text-align:right;">
                    <div style="font-size:11px;color:#6b7280;">Interest only</div>
                    <div style="font-size:22px;font-weight:700;color:#16a34a;font-family:'DM Mono',monospace;">
                        R{recommended['interest']:.2f}
                    </div>
                    <div style="font-size:11px;color:#6b7280;margin-top:2px;">
                        Fees &nbsp;R{recommended['fees']:.2f}
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

    st.markdown("")
    if st.button("Protect my payment", use_container_width=True, type="primary", key="protect_btn"):
        st.session_state.protection_activated = True
        if not st.session_state.selected_option and recommended:
            st.session_state.selected_option = recommended['name']
        st.session_state.page = 2
        st.rerun()

    col_a, col_b = st.columns(2)
    with col_a:
        if st.button("Compare all options", use_container_width=True, key="options_link"):
            st.session_state.page = 3
            st.rerun()
    with col_b:
        if st.button("← Back", use_container_width=True, key="back_msg"):
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
    # Use user-selected option if set, otherwise fall back to recommended
    selected_name = st.session_state.get('selected_option')
    chosen = next((o for o in options if o['name'] == selected_name), recommended)
    cost = chosen['grand_total'] - shortfall if chosen else 0

    st.balloons()

    st.markdown(f"""
    <div class="confirm-hero">
        <div style="font-size:48px;margin-bottom:8px;">✅</div>
        <div style="font-size:22px;font-weight:700;">Payment secured</div>
        <div style="font-size:14px;color:#94a3b8;margin-top:6px;">
            {user_data['debit_order_recipient']} will go through on {user_data['debit_order_date'].strftime('%d %B')}
        </div>
    </div>
    """, unsafe_allow_html=True)

    if chosen:
        c1, c2, c3 = st.columns(3)
        c1.metric("Amount covered", f"R{shortfall:,.0f}")
        c2.metric("Total cost", f"R{cost:.2f}")
        c3.metric("Repay on", user_data['inflow_date'].strftime('%d %b'))
        facility_note = f" via {chosen['name']}" if selected_name and selected_name != (recommended['name'] if recommended else '') else ""
        st.success(f"R{chosen['grand_total']:,.2f} will be automatically deducted from your salary deposit on {user_data['inflow_date'].strftime('%d %B %Y')}{facility_note}. Nothing more to do.")

    col1, col2 = st.columns(2)
    with col1:
        if st.button("Done", use_container_width=True, type="primary"):
            st.session_state.page = 0
            st.rerun()
    with col2:
        if st.button("View details", use_container_width=True, key="view_details"):
            st.session_state.page = 3
            st.rerun()


# ── PAGE 3 — Compare options ──────────────────────────────────────────────────

def show_options_screen():
    st.markdown("### Compare Options")
    st.caption("All eligible facilities · Costs shown for your scenario")
    st.divider()

    shortfall = user_data['predicted_shortfall']
    days = (user_data['inflow_date'] - current_date).days
    rci_score = calculate_rci(user_data, days=days)
    rci_tier, rci_label, rci_color, rci_bg = get_rci_tier(rci_score)
    options = get_credit_options(shortfall, days, user_data, rci_tier, rci_score)
    recommended = get_recommended_option(options, days, rci_tier)

    st.markdown(f"""
    <div style="background:#0A1628;border-left:4px solid #334155;
        padding:10px 14px;border-radius:8px;margin-bottom:16px;font-size:13px;color:#e2e8f0;">
        <strong style="color:white;">RCI {rci_score}</strong> &nbsp;·&nbsp; Tier {rci_tier} — {rci_label}
        &nbsp;·&nbsp; {days}-day repayment window
        &nbsp;·&nbsp; Shortfall R{shortfall:,.0f}
    </div>
    """, unsafe_allow_html=True)

    events = user_data['shortfall_events_this_quarter']
    threshold = user_data['max_shortfall_events_threshold']
    st.markdown(f"""
    <div class="guardrail-strip">
        <strong>Guardrails:</strong> {events}/{threshold} shortfall events this quarter &nbsp;·&nbsp;
        {"⚠️ Approaching limit" if events/threshold >= 0.66 else "✅ Within normal range"}
    </div>
    """, unsafe_allow_html=True)

    for opt in options:
        is_rec = recommended and opt['name'] == recommended['name']
        border_color = "#00A651" if is_rec else "#e2e8f0"
        bg_color = "#f0fdf4" if is_rec else "white"
        rec_badge = "&nbsp;<span style='color:#00A651;font-size:11px;font-weight:700;'>Recommended</span>" if is_rec else ""

        # Behavioural view (primary — actual cost for John's window)
        html = (
            f"<div style='border:1.5px solid {border_color};border-radius:12px;padding:16px 18px;margin-bottom:4px;background:{bg_color};'>"
            f"<div style='font-size:10px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;'>Behavioural View &nbsp;·&nbsp; Your actual {opt['days']}-day cost</div>"
            f"<div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;'>"
            f"<div style='font-size:15px;font-weight:700;color:#0A1628;'>{opt['name']}{rec_badge}"
            f"<span style='font-size:12px;font-weight:400;color:#6b7280;margin-left:6px;'>{opt['rate']}% p.a.</span></div>"
            f"<div style='font-size:22px;font-weight:800;color:#0A1628;font-family:monospace;'>R{opt['grand_total']:.2f}</div>"
            f"</div>"
            f"<div style='display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:12px;'>"
            f"<div style='background:#f8fafc;border-radius:8px;padding:10px 12px;'><div style='font-size:10px;color:#94a3b8;font-weight:600;text-transform:uppercase;margin-bottom:4px;'>Amount</div><div style='font-size:15px;font-weight:700;color:#0A1628;'>R{opt['amount']:,.0f}</div></div>"
            f"<div style='background:#f8fafc;border-radius:8px;padding:10px 12px;'><div style='font-size:10px;color:#94a3b8;font-weight:600;text-transform:uppercase;margin-bottom:4px;'>Interest ({opt['days']}d)</div><div style='font-size:15px;font-weight:700;color:#0A1628;'>R{opt['interest']:.2f}</div></div>"
            f"<div style='background:#f8fafc;border-radius:8px;padding:10px 12px;'><div style='font-size:10px;color:#94a3b8;font-weight:600;text-transform:uppercase;margin-bottom:4px;'>Fees</div><div style='font-size:15px;font-weight:700;color:#0A1628;'>R{opt['fees']:.2f}</div></div>"
            f"<div style='background:#f8fafc;border-radius:8px;padding:10px 12px;'><div style='font-size:10px;color:#94a3b8;font-weight:600;text-transform:uppercase;margin-bottom:4px;'>RALC</div><div style='font-size:15px;font-weight:700;color:#5b21b6;'>R{opt['ralc']:.2f}</div></div>"
            f"</div>"
            f"<div style='font-size:12px;color:#4b5563;border-top:1px solid #e2e8f0;padding-top:10px;'>{opt['note']}</div>"
            f"</div>"
        )
        st.markdown(html, unsafe_allow_html=True)

        # Select button — user can override recommendation
        is_selected = st.session_state.selected_option == opt['name']
        btn_label = "Selected" if is_selected else "Select this option"
        btn_type = "primary" if is_selected else "secondary"
        if st.button(btn_label, key=f"select_{opt['name']}", use_container_width=True, type=btn_type):
            st.session_state.selected_option = opt['name']
            st.rerun()

        # Regulatory view — collapsed expander per card, overdraft only (revolving facility)
        if opt['name'] == 'Overdraft':
            reg = calculate_regulatory_cost(
                user_data['overdraft_limit'],
                user_data['overdraft_rate'],
                user_data['overdraft_monthly_fee']
            )
            with st.expander("Regulatory View — NCA disclosure (full limit, 12-month illustration)"):
                st.markdown(f"""
<div style='background:#f1f5f9;border-radius:8px;padding:12px 16px;font-size:13px;'>
<div style='color:#64748b;font-size:11px;font-weight:700;text-transform:uppercase;margin-bottom:8px;'>If full R{user_data['overdraft_limit']:,} limit used · Repaid over 12 months</div>
</div>""", unsafe_allow_html=True)
                total_cost = reg['total_interest'] + reg['total_fees']
                c1, c2, c3 = st.columns(3)
                c1.metric("Monthly instalment", f"R{reg['monthly_instalment']:,.2f}")
                c2.metric("Total you repay", f"R{reg['total_repayment']:,.2f}")
                c3.metric("Total cost to you", f"R{total_cost:,.2f}")
                st.caption(
                    f"You borrow R{user_data['overdraft_limit']:,} and repay R{reg['total_repayment']:,.2f} over 12 months. "
                    f"The R{total_cost:,.2f} difference is what it actually costs — "
                    f"R{reg['total_interest']:,.2f} in interest + R{reg['total_fees']:,.2f} in monthly service fees. "
                    f"NCA requires this worst-case illustration. John's real cost for R800 over {days} days is R{options[0]['grand_total'] - options[0]['amount']:.2f}."
                )

        st.markdown("<div style='margin-bottom:8px;'></div>", unsafe_allow_html=True)

    st.markdown("---")
    selected_name = st.session_state.get('selected_option')
    if selected_name:
        st.success(f"You have selected: **{selected_name}**")
        if st.button("Confirm and protect my payment", use_container_width=True, type="primary", key="confirm_from_options"):
            st.session_state.protection_activated = True
            st.session_state.page = 2
            st.rerun()
    else:
        st.info("Select an option above to proceed.")

    if st.button("Back", use_container_width=True, key="back_from_options"):
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

    st.markdown(f"""
    <div style="background:{rci_bg};border-left:4px solid {rci_color};
        padding:8px 12px;border-radius:6px;margin-bottom:12px;font-size:13px;">
        <strong>RCI at {calc_days}-day horizon:</strong>
        <span style="font-size:18px;font-weight:800;color:{rci_color};margin:0 6px;">{rci_score}</span>
        Tier {rci_tier} — {rci_label}
    </div>
    """, unsafe_allow_html=True)

    if not options:
        st.warning("No eligible facilities for this combination.")
    else:
        for opt in options:
            is_rec = recommended and opt['name'] == recommended['name']
            if is_rec:
                st.success(f"**{opt['name']} (Recommended)**")
            else:
                st.info(f"**{opt['name']}**")
            c1, c2, c3 = st.columns(3)
            c1.metric("Cost of Liquidity", f"R{opt['grand_total'] - opt['amount']:.2f}")
            c2.metric("Total to Repay", f"R{opt['grand_total']:,.2f}")
            c3.metric("RALC", f"R{opt['ralc']:.2f}", help="Risk-Adjusted Liquidity Cost")
            st.caption(f"Rate {opt['rate']}% p.a. · Best for: {opt['optimal_for']}")
            st.divider()

    if st.button("← Back to Messages", use_container_width=True):
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

# ── Bottom nav ────────────────────────────────────────────────────────────────
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
        color = "#00A651" if is_active else "#9ca3af"
        underline = "border-bottom: 2px solid #00A651; padding-bottom: 2px;" if is_active else ""
        st.markdown(
            f"<div style='text-align:center;font-size:11px;font-weight:600;color:{color};{underline}'>{label}</div>",
            unsafe_allow_html=True
        )
        if st.button(label, key=f"nav_{p}", use_container_width=True, label_visibility="collapsed"):
            st.session_state.page = p
            st.rerun()
