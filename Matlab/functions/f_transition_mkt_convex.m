function f_transition_mkt_convex(init_ss,final_ss,file_out,trans_x,file_suffix)
%
% Solution method
%   1. Do full backward induction
%   2. Iterate ONE time step forward, clear price for that time step
%   3. Starting from that time step (or two ahead), do backward induction.
%   3. Iterate one time step again, check market clearing. If so, move
%   forward again.

if nargin==2
    file_in = [];
elseif nargin>=3
    file_in = [file_out '/'];
end

try
    T = trans_x.Tmax;
catch
    T = 100;
    T=55;
end
tcut = min(5,round(.2*T));

% storage
vf_t = cell(T,1);
pol_t = cell(T,1);
gr_t = cell(T,1);
P_t = ones(T,1);
new_C_t = zeros(T,1);
old_C_t = zeros(T,1);
diff_C_t = zeros(T,1);
diff_C_t_old = diff_C_t;

% load initial steady state
load([file_in init_ss], 'Px', 'par2', 'gr', 'N', 'Pnow', 'old_C')
g0_autarky = squeeze(Px.g_ss);
P_autarky = Pnow;
C_autarky = old_C;
par_t0 = par2;
kmax_autarky = gr.k_grid(end);
par_t0.kstar = kmax_autarky;
gr0.k_grid = gr.k_grid;
% when debugging
try
    load([file_in init_ss], 'Pss_notrade')
    Q_autarky = Pss_notrade;
    clear Pss_notrade
    
catch
    Q_autarky = P_autarky;
    
end
clear Px Pnow par gr new_C

% load final steady state
load([file_in final_ss], 'initval', 'pol', 'par2', 'Pf', 'dM', 'Pnow', 'old_C')
vf_t{end} = initval.Ev;
pol_t{end} = pol;
P_trade = Pnow;
C_trade = old_C;
P_t(:) = Pnow;
par_tT = par2;
new_C_t(end) = old_C;
old_C_t(end) = old_C;
Pf_trade = Pf;
dM_trade = dM;
clear initval pol Pnow par new_C Pf dM

if nargin<=3
    % assume 1 year transition, Pf fixed
    trans_x.Pf = 0;
    trans_x.T = 1;
end
if trans_x.Pf == 0
    % let price be constant
    Pf_t = repmat(Pf_trade,1,T);
else
    % price also moves with dM
    Pf_t = linspace(10*Pf_trade,Pf_trade,trans_x.T);
    Pf_t = [Pf_t(2:end) repmat(Pf_trade,1,T-trans_x.T)];
end

dM_t = linspace(0,dM_trade,trans_x.T);
dM_t = [dM_t(2:end) repmat(dM_trade,1,T-trans_x.T+1)];

P_t_new = P_t;

damp_p = .8;

% trans_x contains switch for fixedR since par_in is not passed in here
% par_t0.fixedR = trans_x.fixedR;


%% solve time path

iter_max = 200;
tol_x = 1e-5;
tol_c = 1e-3;

for iter = 1:iter_max
    
    if iter<50
        relx = 0.1;
    else
        relx = 0.01;
    end
    
    %%% full backward induction step (only needed for first iteration)
    for t=T-1:-1:1

        % always reset to t0 par
        par2 = par_t0;

        % next period value function
        initval.Ev = vf_t{t+1};
        % next period price
        par2.P_pr = P_t(t+1);
        % this period price
        par2.P = P_t(t);
        % last period price
        par2.P_last = P_t(max(1,t-1));
        % fix price of capital
        par2.Q = Q_autarky;
        % foreign price
        Pf = Pf_t(t);
        % foreign mass of firms
        dM = dM_t(t);
        % time / t0 k_grid
        if par2.lam==0 && par2.zet==0
            par2.t = t;
            par2.k_grid = gr0.k_grid;
        end

        %%% set the grid
        gr = mainfuncMP_convex(par2,N,[],[],2);

        %%% solve the individual's problem by backward induction
        output  = mainfuncMP_convex(par2,N,gr,[],5,initval);
        pol     = output.pol;
        v       = output.vf;
        clear output

        gr.i_inact_xgrid = [];
        gr.k_inact_xgrid = [];
        gr.i_inact_xgrid = [];
        gr.s_xgrid0 = [];
        gr.tau_xgrid = [];
        gr.x_xgrid = [];
        gr.s_xgrid = [];
        gr.py_i = [];
        gr.y_tau = [];
        if t>1
            gr.k_xgrid = [];
        end

        vf_t{t} = v;
        pol_t{t} = pol;
        gr_t{t} = gr;

    end
    
    %%% forward iteration step
    g0 = g0_autarky;
    clear initval
    for t=1:T-1
        
        %%% clear the market at time t
        % always reset to t0 par
        par_in = par_t0;
        % next period price
        par_in.P_pr = P_t(t+1);
        % last period price
        par_in.P_last = P_t(max(1,t-1));
        % fix price of capital
        par_in.Q = Q_autarky;
        % foreign price
        Pf = Pf_t(t);
        % foreign mass of firms
        dM = dM_t(t);
        % time / t0 k_grid
        if par_in.lam==0 && par_in.zet==0
            par_in.t = t;
            par_in.k_grid = gr0.k_grid;
        end

        % clear market
        Pnew = fzero(@(P0) mkt_static(P0,par_in,N,Pf,dM,g0), P_t(t),optimset('TolX',tol_x));
        if t>=2
            Pnew = (1-damp_p)*P_t(t) + damp_p*Pnew;
        end

        % save price
%         P_t_new(t) = Pnew;
        P_t_new(t) = min(Pnew,P_t(end));
        if iter>1
            P_t_new(t) = max(P_t_new(t),P_t(1));
        end
        
        % sort to avoid instability
%         P_t_new = sort(P_t_new);
        P_t_new = sort_P(P_t_new,P_autarky,P_trade,trans_x);
        
    
        % always reset to t0 par
        par2 = par_t0;
        % next period price (use original guess)
        par2.P_pr = P_t(t+1);
        % this period price (use current solution)
        par2.P = P_t_new(t);
        % fix price of capital
        par2.Q = Q_autarky;
        % foreign price
        Pf = Pf_t(t);
        % foreign mass of firms
        dM = dM_t(t);
        % time / t0 k_grid
        if par2.lam==0 && par2.zet==0
            par2.t = t;
            par2.k_grid = gr0.k_grid;
        end

        %%% averages computed using starting distribution!
        % implied total consumption given guess of P
        old_C = 1/(par2.P*par2.chi);
        % inner integral for domestic goods
        inner_Cd = gr_t{t}.y_i(:).^((par2.epsi-1)/par2.epsi)'*g0(:);
        % inner integral for foreign goods
        inner_Cf = (Pf.^(-par2.epsi)*(par2.P^par2.epsi)*old_C)^((par2.epsi-1)/par2.epsi)*dM;
        cf_i = Pf.^(-par2.epsi)*(par2.P^par2.epsi)*old_C; % individual foreign firm
        % actual consumption
        new_C = (inner_Cd + inner_Cf)^(par2.epsi/(par2.epsi-1));

        %%% store new consumption
        new_C_t(t) = new_C;
        old_C_t(t) = old_C;
        diff_C_t(t) = new_C - old_C;

        % push distribution forward
        initval.g0 = g0(:);
        initval.trmat = [];
        output2 = mainfuncMP_convex(par2,N,gr_t{t},pol_t{t},6,initval);
        g0  = output2.g1(:);
        clear initval
    end
    
    % check convergence using prices
    diff_P_t = P_t_new - P_t;
    
    % plot progression
    close all
    subplot(311)
    plot(diff_P_t)
    subplot(312)
    hold on
    plot(diff_C_t_old)
    plot(diff_C_t)
    hold off
    subplot(313)
    plot(1:T,P_t,1:T,P_t_new)
    drawnow
   
    if max(abs(diff_P_t(:)))<10*tol_x
        tol_c = 1e-3;
    end
    
    % check market clearing errors
    if max(abs(diff_P_t(:)))<tol_x || max(abs(diff_C_t(:)))<tol_c
        break
    end
    
    % update price
    if iter == 1
        P_t = P_t_new;
    else
        P_t = (1-damp_p)*P_t + damp_p*P_t_new;
    end
    
    % lower dampening as prices converge
    if max(abs(diff_C_t(:)))< 2e-2
        damp_p = .5;
    end
    if iter > 5 && par_t0.zet>0
        damp_p = 0.25;
    end
   
    % check market clearing error at T-1
    if abs(diff_C_t(end-1)) < tol_c*0.1 && abs(P_t(end)-P_t(end-1))<=tol_x && T>25
        % truncate length of soln
        T_new = T-1;
        
        P_t_x = P_t(1:T_new);
        P_t_x(end) = P_t(end);
        
        vf_t_x = vf_t(1:T_new);
        vf_t_x(end) = vf_t(end);
        
        dM_t_x = dM_t(1:T_new);
        dM_t_x(end) = dM_t(end);
        
        Pf_t_x = Pf_t(1:T_new);
        Pf_t_x(end) = Pf_t(end);
        
        diff_C_t_x = diff_C_t(1:T_new);
        diff_C_t_x(end) = diff_C_t(end);
        
        gr_t = gr_t(1:T_new);
        pol_t = pol_t(1:T_new);
        
        % storage
        new_C_t = zeros(T_new,1);
        old_C_t = zeros(T_new,1);

        % update
        P_t = P_t_x;
        P_t_new = P_t;
        vf_t = vf_t_x;
        dM_t = dM_t_x;
        Pf_t = Pf_t_x;
        diff_C_t = diff_C_t_x;
        clear *_t_x
        
        T = T_new;

    end
    
    diff_C_t_old = diff_C_t;
    diff_C_t = 0*diff_C_t;
end

%% Compute statistics along transition path

C_t = zeros(T-1,1);
Cd_t = zeros(T-1,1);
Cf_t = zeros(T-1,1);
P_Cd_t = zeros(T-1,1);
P_Cf_t = zeros(T-1,1);
Kd_t = zeros(T-1,1);
Ld_t = zeros(T-1,1);
L_t = zeros(T-1,1);
TFPR_t = zeros(T-1,1);
TFPQ_t = zeros(T-1,1);
Mentrants_t = zeros(T-1,1);
Mactive_t = zeros(T-1,1);
Mexit_t = zeros(T-1,1);

% Aggregates
IK_t = zeros(T-1,1);
I_Gross_t = zeros(T-1,1);
I_Gross_plus_t = zeros(T-1,1);
I_Gross_neg_t = zeros(T-1,1);
I_net_t = zeros(T-1,1);

% Expected values
I_Gross_intensive_t = zeros(T-1,1);
I_Gross_plus_intensive_t = zeros(T-1,1);
I_Gross_neg_intensive_t = zeros(T-1,1);
I_Gross_frac_0_intensive_t = zeros(T-1,1);
I_Gross_frac_pos_intensive_t = zeros(T-1,1);
I_Gross_frac_neg_intensive_t = zeros(T-1,1);
I_Gross_frac_intensive_neg_t = zeros(T-1,1);

operating_cost_t = zeros(T-1,1);
entry_cost_t = zeros(T-1,1);

avg_raw_s_t = zeros(T-1,1);
avg_wgt_s_t = zeros(T-1,1);
avg_wgt_y_s_t = zeros(T-1,1);
avg_wgt_k_s_t = zeros(T-1,1);

avg_raw_s_entrants_t = zeros(T-1,1);
avg_raw_s_exiters_t = zeros(T-1,1);
avg_raw_s_cont_t = zeros(T-1,1);

avg_s_med = zeros(T-1,1);
avg_s_med_2 = zeros(T-1,1);

mean_mpk_t = zeros(T-1,1);
sd_mpk_t = zeros(T-1,1);
sd_log_s_t = zeros(T-1,1);
sd_s_next_t = zeros(T-1,1);

avg_k_exit_t = zeros(T-1,1);
avg_k_cont_t = zeros(T-1,1);
avg_k_enter_t = zeros(T-1,1);
avg_frac_neg_kpr_t = zeros(T-1,1);
    
g0 = g0_autarky;
clear initval
for t=1:T-1

    % always reset to t0 par
    par2 = par_t0;
    % next period price
    par2.P_pr = P_t(t+1);
    % this period price
    par2.P = P_t(t);
    % last period price
    par2.P_last = P_t(max(1,t-1));
    % fix price of capital
    par2.Q = Q_autarky;
    % foreign price
    Pf = Pf_t(t);
    % foreign mass of firms
    dM = dM_t(t);
    % time / t0 k_grid
    if par2.lam==0 && par2.zet==0
        par2.t = t;
        par2.k_grid = gr0.k_grid;
    end
    
    %%% recreate grid
    gr_now = mainfuncMP_convex(par2,N,[],[],2);

    %%% averages computed using starting distribution!
    % implied total consumption given guess of P
    old_C = 1/(par2.P*par2.chi);
    % inner integral for domestic goods
    inner_Cd = gr_now.y_i(:).^((par2.epsi-1)/par2.epsi)'*g0(:);
    % inner integral for foreign goods
    inner_Cf = (Pf.^(-par2.epsi)*(par2.P^par2.epsi)*old_C)^((par2.epsi-1)/par2.epsi)*dM;
    cf_i = Pf.^(-par2.epsi)*(par2.P^par2.epsi)*old_C; % individual foreign firm
    % actual consumption
    new_C = (inner_Cd + inner_Cf)^(par2.epsi/(par2.epsi-1));
    % Domestic real output
    Cd = inner_Cd^(par2.epsi/(par2.epsi-1));

   
    %%% Measure of firms
    g0  = squeeze(g0);                                 % distribution of active firms
    g0_entrants = pol_t{t}.pr_fstar_enter(:).*gr_now.ps_dist(:);     % distribution of entrants
    g0_stay = pol_t{t}.pr_stay(:).*g0(:);                        % distribution stayers
    g0_exit = (1-pol_t{t}.pr_stay(:)).*g0(:);                    % distribution exiters

    %%% Grids
    incx_gr = pol_t{t}.kpr - (1-par2.delta)*gr_now.k_xgrid;    % gross investment grid
    xi = (exp(log(pol_t{t}.kpr)-log(gr_now.k_xgrid)) - (1-par2.delta)).^2.*gr_now.k_xgrid; % convex adj cost
    Qq = par2.Q*(1-par2.lam*(incx_gr<0));
    incx_gr_true = Qq.*incx_gr + par2.c1*xi;                     % gross investment grid, factoring in q and Q and convex cost
    ik_i = incx_gr(:)./gr_now.k_xgrid(:);                   % firm level i/k
    kpr_entrants = pol_t{t}.kpr_up;                          % investment grid of entrants

    %%% Aggregates
    C = 1/(par2.P*par2.chi);    % total consumption of final good
    try 
        Cf = cf_i*dM;               % total physical consumption, foreign goods
        P_Cf = Pf*cf_i*dM;          % total real revenue of foreign firms
    catch
        Cf = 0;
        P_Cf = 0;
    end
    P_Cd = gr_now.py_i(:)'*g0(:);   % total real revenue of domestic firms
    Kd = gr_now.k_xgrid(:)'*g0(:);  % total capital stock of domestic firms
    Ld = gr_now.lstar(:)'*g0(:);    % total labor of domestic firms
    TFPR = P_Cd/(Kd^par2.alph * Ld^(1-par2.alph)); % TFPR of domestic firms

    %%% Investment aggregates (need to account for change in measure)
    window = 0.00;
    % aggregates
    IK = ik_i'*g0_stay(:);                                  % Average I/K of stayers
    I_Gross = incx_gr(:)'*g0_stay(:) + ...
            (1-par2.delta)*(-1*gr_now.k_xgrid(:))'*g0_exit + ...
            kpr_entrants(:)'*g0_entrants(:);                % Gross inv incl stayers, exit and entry
    I_Gross_plus = (incx_gr(:).*(incx_gr(:)>window))'*g0_stay(:) + ...
            kpr_entrants(:)'*g0_entrants(:);                % Gross +ve incl stayers and entry;
    I_Gross_neg = (abs(incx_gr(:)).*(incx_gr(:)<-window))'*g0_stay(:) ...
            + (1-par2.delta)*gr_now.k_xgrid(:)'*g0_exit;      % Gross -ve incl stayers and exits
    I_net = incx_gr_true(:)'*g0_stay(:) + ...
            (1-par2.zet)*par2.Q*(1-par2.lam)*(1-par2.delta)*(-1*gr_now.k_xgrid(:)'*g0_exit) + ...
            par2.Q*kpr_entrants(:)'*g0_entrants(:);                % Net inv incl stayers, exit, and entry
    % Expected values (measures normalized to 1)
    I_Gross_intensive = incx_gr(:)'*g0_stay(:)/sum(g0_stay(:)); % Gross inv along intensive margin
    I_Gross_plus_intensive = (incx_gr(:).*(incx_gr(:)>window))'*g0_stay(:)/sum(g0_stay); % Gross inv along intensive margin
    I_Gross_neg_intensive = (abs(incx_gr(:)).*(incx_gr(:)<-window))'*g0_stay(:)/sum(g0_stay); % Gross inv along intensive margin
    I_Gross_frac_intensive_neg = (incx_gr(:) < -window)'*g0_stay(:)/sum(g0_stay(:)); % Total fraction of negative investment
    I_Gross_frac_0_intensive = (incx_gr(:)>=-window & incx_gr(:)<=window)'*g0_stay(:)/sum(g0_stay(:)); % Total fraction of inaction of stayers
    I_Gross_frac_pos_intensive = (incx_gr(:) > window)'*g0_stay(:)/sum(g0_stay(:)); % Total fraction of pos investment of stayers
    I_Gross_frac_neg_intensive = (incx_gr(:) < -window)'*g0_stay(:)/sum(g0_stay(:)); % Total fraction of neg investment of stayers

    %%% Other costs, labor and welfare
    operating_cost = pol_t{t}.Ef_pr(:)'*g0_stay(:); % total operating costs paid
    entry_cost = pol_t{t}.Ef_enter(:)'*g0_entrants(:); % total entry costs paid
    L = Ld + I_net + operating_cost + entry_cost + P_Cf; % total labor (domestic + investment goods + fixed costs + export)

    %%% Raw average of TFPQ
    avg_raw_s = gr_now.s_xgrid0(:)'*g0(:)/sum(g0(:));
    
    %%% weighted average of TFPQ (PY)
    PY_domestic = gr_now.py_i(:)'*g0(:); % PY as denom
    wgt_py = (gr_now.py_i(:).*g0(:))/PY_domestic; % wgts, PY
    avg_wgt_s = gr_now.s_xgrid0(:)'*wgt_py;
    
    %%% weighted average of TFPQ (Y)
    Y_domestic = gr_now.y_i(:)'*g0(:); % Y as denom
    wgt_y = (gr_now.y_i(:).*g0(:))/Y_domestic; % wgts, Y
    avg_wgt_y_s = gr_now.s_xgrid0(:)'*wgt_y;    
    
    %%% weighted average of TFPQ (K)
    K_domestic = gr_now.k_xgrid(:)'*g0(:); % K as denom
    wgt_k = (gr_now.k_xgrid(:).*g0(:))/K_domestic; % wgts, K
    avg_wgt_k_s = gr_now.s_xgrid0(:)'*wgt_k;    
    
    %%% Average TFPQ of entrants
    avg_raw_s_entrants = gr_now.s_grid(:)'*g0_entrants(:)/sum(g0_entrants(:));
    
    %%% Average TFPQ of exiters
    avg_raw_s_exiters = gr_now.s_xgrid0(:)'*g0_exit(:)/sum(g0_exit(:));
    
    %%% Average TFPQ of continuers
    avg_raw_s_cont = gr_now.s_xgrid0(:)'*g0_stay(:)/sum(g0_stay(:));
    
    %%% MPK dispersion
    mpk_grid = log(gr_now.py_i) - log(gr_now.k_xgrid) + log(par2.alpha_k);
    mean_mpk = mpk_grid(:)'*g0(:)/sum(g0(:));
    sd_mpk = sqrt((mpk_grid(:)'-mean_mpk).^2 * g0(:)/sum(g0(:)));
    
    %%% s.d. TFPQ
    avg_log_s = log(gr_now.s_xgrid0(:))'*g0(:)/sum(g0(:));
    sd_log_s = sqrt((log(gr_now.s_xgrid0(:)')-avg_log_s).^2 * g0(:)/sum(g0(:)));
    
    %%% s.d. TFPQ of continuers
    g0_stay_1d = sum(reshape(g0_stay,size(gr_now.s_xgrid0)),2);
    g0_next = g0_stay_1d + g0_entrants;
    avg_s = gr_now.s_grid(:)'*g0_next(:)/sum(g0_next(:));
    sd_s_next = sqrt((gr_now.s_grid(:)'-avg_s).^2 * g0_next(:)/sum(g0_next(:)));

    g0_s = sum(reshape(g0,N.s,N.k),2);
    cdf_g0_s = cumsum(g0_s)/sum(g0_s);
    is = find(cdf_g0_s>=0.5,1,'first');
    s_med = gr_now.s_grid(1:is);
    cdf_med = cdf_g0_s(1:is);
    s_med_2 = gr_now.s_grid(is+1:end);
    cdf_med_2 = cdf_g0_s(is+1:end);
    avg_s_med(t) = s_med(:)'*cdf_med(:)/sum(cdf_med(:));
    avg_s_med_2(t) = s_med_2(:)'*cdf_med_2(:)/sum(cdf_med_2(:));

    % Measured corrected TFP
    M_norm = sum(g0(:)).^(1/(par2.epsi-1));
    TFPQ = Cd./(M_norm.*(Kd.^par2.alph .* Ld.^(1-par2.alph)));

    %%% store statistics
    C_t(t) = C;
    Cd_t(t) = Cd;
    Cf_t(t) = Cf;
    P_Cd_t(t) = P_Cd;
    P_Cf_t(t) = P_Cf;
    Kd_t(t) = Kd;
    Ld_t(t) = Ld;
    L_t(t) = L;
    TFPR_t(t) = TFPR;
    TFPQ_t(t) = TFPQ;
    Mentrants_t(t) = sum(g0_entrants(:));
    Mactive_t(t) = sum(g0(:));
    Mexit_t(t) = sum(g0_exit(:));

    IK_t(t) = IK;
    I_Gross_t(t) = I_Gross;
    I_Gross_plus_t(t) = I_Gross_plus;
    I_Gross_neg_t(t) = I_Gross_neg;
    I_net_t(t) = I_net;
    I_Gross_intensive_t(t) = I_Gross_intensive;
    I_Gross_plus_intensive_t(t) = I_Gross_plus_intensive;
	I_Gross_neg_intensive_t(t) = I_Gross_neg_intensive;
    I_Gross_frac_0_intensive_t(t) = I_Gross_frac_0_intensive;
    I_Gross_frac_pos_intensive_t(t) = I_Gross_frac_pos_intensive;
    I_Gross_frac_neg_intensive_t(t) = I_Gross_frac_neg_intensive;
    I_Gross_frac_intensive_neg_t(t) = I_Gross_frac_intensive_neg;

    operating_cost_t(t) = operating_cost;
    entry_cost_t(t) = entry_cost;
    
    avg_raw_s_t(t) = avg_raw_s;
    avg_wgt_s_t(t) = avg_wgt_s;
    avg_wgt_y_s_t(t) = avg_wgt_y_s;
    avg_wgt_k_s_t(t) = avg_wgt_k_s;
    
    avg_raw_s_entrants_t(t) = avg_raw_s_entrants;
    avg_raw_s_exiters_t(t) = avg_raw_s_exiters;
    avg_raw_s_cont_t(t) = avg_raw_s_cont;
    
    mean_mpk_t(t) = mean_mpk;
    sd_mpk_t(t) = sd_mpk;
    sd_log_s_t(t) = sd_log_s;
    sd_s_next_t(t) = sd_s_next;
    
    % average k of exiters
    avg_k_exit_t(t) = gr_now.k_xgrid(:)'*g0_exit(:)/sum(g0_exit(:));
    % average k of continuers
    avg_k_cont_t(t) = gr_now.k_xgrid(:)'*g0_stay(:)/sum(g0_stay(:));
    % average k of entrants
    avg_k_enter_t(t) = kpr_entrants(:)'*g0_entrants(:)/sum(g0_entrants(:));
    % probs k'/k<0 for continuers
    neg_kpr_gr = pol.kpr < gr_now.k_xgrid;
    avg_frac_neg_kpr_t(t) = neg_kpr_gr(:)'*g0_stay(:)/sum(g0_stay(:));

    % push distribution forward
    initval.g0 = g0(:);
    initval.trmat = [];
    output2 = mainfuncMP_convex(par2,N,gr_now,pol_t{t},6,initval);
    g0  = output2.g1(:);

end


%% export full workspace

clear gr_t vf_t
if nargin==5
    % file path and suffix are both supplied
    if par2.lam>0
        save([file_out '/transition' file_suffix],'*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    else
        save([file_out '/transition_q1' file_suffix],'*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    end
    
elseif nargin>=3 && nargin<5
    % only file path supplied
    if par2.lam>0
        save([file_out '/transition'],'*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    else
        save([file_out '/transition_q1'],'*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    end
    
else
    % no file path supplied
    mkdir('mat_files')
    if par2.lam>0
        save('mat_files/transition','*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    else
        save('mat_files/transition_q1','*_t', 'T', '*_autarky', '*_t0', 'par*','-v7.3')
    end
    
end

end


%%

function xcons = mkt_static(P_now,par_in,N,Pf,dM,g0)

    % set current price
    par_in.P = P_now;
    
    % set the grid
    gr_now = mainfuncMP_convex(par_in,N,[],[],2);

    %%% averages at t
    % implied total consumption given guess of P
    old_C = 1/(par_in.P*par_in.chi);
    % inner integral for domestic goods
    inner_Cd = gr_now.y_i(:).^((par_in.epsi-1)/par_in.epsi)'*g0(:);
    % inner integral for foreign goods
    inner_Cf = (Pf.^(-par_in.epsi)*(par_in.P^par_in.epsi)*old_C)^((par_in.epsi-1)/par_in.epsi)*dM;
    cf_i = Pf.^(-par_in.epsi)*(par_in.P^par_in.epsi)*old_C; % individual foreign firm
    % actual consumption
    new_C = (inner_Cd + inner_Cf)^(par_in.epsi/(par_in.epsi-1));

    % check excess demand
    xcons = new_C - old_C;

end

%%

function [xcons,v,pol,gr_now] = mkt_static_val(P_now,par_in,N,Pf,dM,g0,initval)

    % set current price
    par_in.P = P_now;

    % set the grid
    gr_now = mainfuncMP_convex(par_in,N,[],[],2);
    
    % solve the individual's problem by backward induction
    output  = mainfuncMP_convex(par_in,N,gr_now,[],5,initval);
    pol     = output.pol;
    v       = output.vf;
    clear output

    %%% averages at t
    % implied total consumption given guess of P
    old_C = 1/(par_in.P*par_in.chi);
    % inner integral for domestic goods
    inner_Cd = gr_now.y_i(:).^((par_in.epsi-1)/par_in.epsi)'*g0(:);
    % inner integral for foreign goods
    inner_Cf = (Pf.^(-par_in.epsi)*(par_in.P^par_in.epsi)*old_C)^((par_in.epsi-1)/par_in.epsi)*dM;
    cf_i = Pf.^(-par_in.epsi)*(par_in.P^par_in.epsi)*old_C; % individual foreign firm
    % actual consumption
    new_C = (inner_Cd + inner_Cf)^(par_in.epsi/(par_in.epsi-1));

    % check excess demand
    xcons = new_C - old_C;

end

%%
function P_t_out = sort_P(P_t_in,P_start,P_end,trans_x)

    if trans_x.T == 1
        P_t = sort(P_t_in);
%         P_t(end-5:end) = P_end;
    elseif trans_x.T > 1 && trans_x.T<=5
        P_t_s = sort(P_t_in(trans_x.T+3:end));
        P_t = [P_t_in(1:trans_x.T+2)' P_t_s(:)'];
    else
        P_t = P_t_in;
        P_t(end) = P_trade;
    end

    if P_start > P_end
        P_t_out = P_t;
    elseif P_start < P_end
        P_t_out = P_t(end:-1:1);
    else
        P_t_out = P_t;
    end
    
%         if max(abs(diff_C_t(:)))<0.5
%             P_t1 = P_t(1:trans_x.T+2);
%             P_t2 = smooth(P_t(trans_x.T+3:end));
%             P_t = [P_t1(:) ; P_t2(:)];
%         end

end
