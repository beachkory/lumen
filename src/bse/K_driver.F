!
!        Copyright (C) 2000-2017 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM
! 
! This file is distributed under the terms of the GNU 
! General Public License. You can redistribute it and/or 
! modify it under the terms of the GNU General Public 
! License as published by the Free Software Foundation; 
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will 
! be useful, but WITHOUT ANY WARRANTY; without even the 
! implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE.  See the GNU General Public License 
! for more details.
!
! You should have received a copy of the GNU General Public 
! License along with this program; if not, write to the Free 
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
subroutine K_driver(Xen,Ken,Xk,q,X_static_pp,Xw)
 !
 use pars,           ONLY:SP,IP
 use parser_m,       ONLY:parser
 use com,            ONLY:msg,warning
 use memory_m,       ONLY:mem_est
 use stderr,         ONLY:string_remove
 use electrons,      ONLY:levels,n_sp_pol,BZ_DbGd_nbands,n_spin
 use frequency,      ONLY:w_samp,W_reset
 use X_m,            ONLY:X_t,X_duplicate,X_reset,global_gauge
 use BS_solvers,     ONLY:BSS_n_freqs,BSS_er,BSS_dr,BSS_mode,BSS_add_antiresonant,BSS_damp_reference,&
&                         BSS_uses_DbGd,BSS_q0,BSS_eval_JDOS
 use BS,             ONLY:BS_bands,BS_q,BS_n_g_exch,BS_K_coupling,BS_res_K_corr,BS_res_K_exchange,&
&                         BS_W_is_diagonal,BS_res_mode,BS_n_g_W,BS_K_is_ALDA,BS_cpl_mode,BS_cpl_K_corr,BS_cpl_K_exchange,&
&                         BSE_mode,BS_Blocks_and_Transitions_free,BS_gamma_point
 use TDDFT,          ONLY:FXC_per_memstps,FXC_n_mem_freqs,FXC_is_retarded,FXC_n_g_corr
 use drivers,        ONLY:l_rpa_IP,l_alda_fxc,l_bs_fxc,l_bss
 use parallel_m,     ONLY:PP_redux_wait,PAR_IND_WF_b_and_k
 use interfaces,     ONLY:PARALLEL_global_indexes,PARALLEL_WF_distribute,PARALLEL_WF_index,eval_G_minus_G
 use R_lattice,      ONLY:bz_samp,qindx_B
#if defined _KERR
 use drivers,        ONLY:l_kerr,l_anomalous_Hall
#endif
#if defined _LU
 use drivers,        ONLY:l_lum
#endif
 !
 implicit none
 !
 type(levels)  ::Xen,Ken
 type(bz_samp) ::Xk,q
 type(X_t)     ::X_static_pp
 type(w_samp)  ::Xw
 !
 ! Work Space
 !
 type(X_t)         :: X_tddft,X_oscillators
 integer           :: iq,Max_G_m_G
 type(w_samp)      :: W_bss 
 !
 call section('*','Response Functions in Transition space')
 !=========================================================
 !
 ! Check if it is a calculation at Gamma Points
 !==============================================
 BS_gamma_point=.FALSE.
 if(Xk%nibz==1) then
   BS_gamma_point=.TRUE.
   call msg('s','[BSE] BSE at Gamma point: uses less memory but slightly slower')
 endif
 !
 ! Joint DOS
 !===========
 BSS_eval_JDOS = index(BSS_mode,'d')/=0.or.l_rpa_IP
 !
 ! Copatibility with old inputs
 !==============================
 if (index(BSE_mode,'causal')/=0) BSE_mode='retarded'
 !
 ! Tranferred momentum. Only Gamma now
 !=====================================
 !
 iq=BS_q(1)
 !
 ! TDDFT setup and Resets
 !========================
 !
 call X_reset(X_tddft)
 call W_reset(W_bss)
 !
 call TDDFT_do_X_W_typs(-1,X_tddft,Xw)
 !
 if(.not.any((/trim(global_gauge)=="velocity".or.trim(global_gauge)=="length"/)) ) then
   call warning(" Not a valid gauge in input. Switching to lenght gauge")
   global_gauge="length"
 endif
 !
 !
 ! W RL size setup looking at the max index of G-G' 
 ! =========
 !
 if (.not.l_rpa_IP) then
   Max_G_m_G=eval_G_minus_G(BS_n_g_W,maxval(qindx_B(:,:,2)))
   if (BS_n_g_W/= Max_G_m_G ) then
     BS_n_g_W= Max_G_m_G
     call warning (' W size reduced due to symmetry constraints')
     call msg('s','[BSE-W] W size forced by symmetry to be :',BS_n_g_W)
   endif
 endif
 !
 !
 ! Logicals (Drivers)
 !====================
 if (l_rpa_IP.and.index(BSE_mode,'coupling')>0) BSE_mode='retarded'
 !
 BS_res_K_corr=index(BS_res_mode,'c')/=0
 BS_res_K_exchange=index(BS_res_mode,'x')/=0
 BS_cpl_K_corr=index(BS_cpl_mode,'c')/=0
 BS_cpl_K_exchange=index(BS_cpl_mode,'x')/=0
 BS_K_coupling=any((/BS_cpl_K_corr,BS_cpl_K_exchange/)) 
 BSS_add_antiresonant=index(BSE_mode,'retarded')/=0
 BS_W_is_diagonal=index(BS_res_mode,'d')/=0
 BS_K_is_ALDA=l_alda_fxc.and.n_spin==1
 if (n_spin>1.and.l_alda_fxc) call warning('TDDFT/ALDA not implemented for n_spin>1. Switched off')
#if defined _KERR
 call parser('EvalKerr',l_kerr)
 if(l_kerr) call parser('AnHall',l_anomalous_Hall)
#endif
 !
#if defined _LU
 call parser('EvalLum',l_lum)
#endif
 ! Energy points
 !===============
 W_bss%n_freqs=BSS_n_freqs
 W_bss%er=BSS_er
 W_bss%dr=BSS_dr
 W_bss%damp_reference=BSS_damp_reference
 !
 ! Double Grid support
 !=====================
 BSS_uses_DbGd = (BZ_DbGd_nbands>=BS_bands(2)) .and. (index(BSS_mode,'i')/=0)
 !
 ! Frequencies 
 !=============
 W_bss%per_memstps=FXC_per_memstps
 call FREQUENCIES_setup(W_bss)
 FXC_n_mem_freqs=W_bss%n_freqs
 !
 ! PARALLEL SETUP
 !================
 call X_duplicate(X_static_pp,X_oscillators) 
 X_oscillators%whoami=5
 X_oscillators%ib(1:2)=BS_bands(1:2)
 X_oscillators%q0=BSS_q0
 !
 ! ... EH space (no parallelization)
 call K_Transitions_setup(iq,Ken,Xk,.FALSE.)
 !
 !... Parallel distribution
 call PARALLEL_global_indexes(Ken,Xk,q,"Response_T_space",X=X_oscillators)
 !
 ! ... EH space (with parallelization) and Transition groups build-up
 call K_Transitions_setup(iq,Ken,Xk,.TRUE.)
 !
 !... Blocks build-up
 if (.not.l_rpa_IP) call K_blocks( )
 !
 ! 1. The IP Part (Dipoles included) ...
 ! ======================================
 call K_IP(iq,Ken,Xk,X_oscillators,W_bss)
 !
 ! Wave Functions distribution (overwrites the one done in K_IP to calculate the oscillators)
 !=============================---------------------------------------------------------------
 call PARALLEL_WF_distribute(B_and_K_index=PAR_IND_WF_b_and_k,CLEAN_UP=.FALSE.)
 !
 call PARALLEL_WF_index( )
 !
 ! 2. The KERNEL
 ! ================
 if (.not.l_rpa_IP) call K(iq,Ken,Xk,q,X_static_pp,Xw,W_bss)
 !
 ! 3. The SOLVER
 ! =================
 if (l_bss) call K_solvers(iq,Ken,Xk,q,X_static_pp,W_bss)
 !
 !
 ! CLEAN (Blocks)
 !
 call BS_Blocks_and_Transitions_free( ) 
 !
end subroutine
