!
!        Copyright (C) 2000-2016 the YAMBO team
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
subroutine O_driver(Xen,Xk,q,wv,X)
 ! 
 ! Optics driver
 !
 ! Calculates dielectric function for a generic q vector.
 ! 
 use pars,          ONLY:pi,SP,cZERO
 use units,         ONLY:HA2EV
 use memory_m,      ONLY:mem_est
 use stderr,        ONLY:intc,set_real_printed_length
 use drivers,       ONLY:l_rpa_IP,l_bs_fxc,l_alda_fxc
 use frequency,     ONLY:w_samp
 use electrons,     ONLY:levels,BZ_DbGd_tot_nkpts
 use R_lattice,     ONLY:bz_samp,q_norm,bare_qpg
 use com,           ONLY:msg,of_open_close
 use X_m,           ONLY:X_t,Epsilon_ii,EEL,Alpha,X_mat,X_alloc,X_fxc,use_covariant_approach, &
&                        use_X_DbGd,eval_alpha,eps_2_alpha,O_eels,Dipole_approach
 use parallel_m,    ONLY:PP_redux_wait,PAR_IND_Q,PAR_COM_Q_A2A,PAR_IND_CON_BANDS_X,&
&                        PAR_IND_Xk_ibz,PAR_IND_VAL_BANDS_X,PAR_COM_DIPOLES
 use wave_func,     ONLY:WF,WF_buffer,WF_buffered_IO
 use TDDFT,         ONLY:FXC_n_descs,FXC_description,FXC_type,&
&                        FXC,FXC_K_diagonal,FXC_n_g_corr
 use X_output,      ONLY:X_setup_file_names,eps_file_name,eel_file_name,alpha_file_name,fxc_file_name,&
&                        X_write_q_plus_G,X_write_descriptions,X_write_messages_before_headers,headers,&
&                        X_setup_headers
#if defined _LU
 use X_output,      ONLY:lum_file_name
 use electrons,     ONLY:nel_cond
 use X_m,           ONLY:Luminescence,Lum_mat
 use com,           ONLY:error,warning
#endif
 use nl_optics,     ONLY:eval_OVERLAPS
 use interfaces,    ONLY:PARALLEL_global_indexes,PARALLEL_WF_index,PARALLEL_WF_distribute,WF_load
 !
 implicit none
 !
 type(levels)  :: Xen
 type(bz_samp) :: Xk,q
 type(X_t)     :: X
 type(w_samp)  :: wv 
 ! 
 ! Work Space
 !
 integer          :: iw,iq,i_G_shift,n_output
 real(SP)         :: output_data(5),Q_plus_G_pt(3),Q_plus_G_sq_modulus
 logical          :: l_skip_non_int_eps,eval_eels
 !
 integer,external :: O_select_q_and_G
 !
 call section('*','Optics')
 !
 ! Basical Checks
 !
 call X_pre_setup(Xen,X)
 !
 call set_real_printed_length(f_length=10,g_length=10)
 !
 do iq=X%iq(1),X%iq(2)
   !
   ! Check if I use covariant dipoles
   ! ================================
   !
   if(iq==1) then
     use_covariant_approach      = trim(Dipole_approach)=='Covariant'
     if(use_covariant_approach) then
       X%ib_lim(1)=X%ib(2)
       X%ib_lim(2)=X%ib(1)
       eval_OVERLAPS=.TRUE.
     endif
   endif
   !
   ! PARALLEL indexes
   !==================
   !
   if (X%iq(1)==1) then
     if (iq==1) call PARALLEL_global_indexes(Xen,Xk,q,"Response_G_space_Zero_Momentum",X=X) 
     if (iq==2) call PARALLEL_global_indexes(Xen,Xk,q,"Response_G_space_Finite_Momentum",X=X) 
   else 
     if (iq==X%iq(1)) call PARALLEL_global_indexes(Xen,Xk,q,"Response_G_space_Finite_Momentum",X=X) 
   endif
   !
   ! WF distribution 
   !=================
   !
   call PARALLEL_WF_distribute(K_index=PAR_IND_Xk_ibz,&
&                              B_index=PAR_IND_CON_BANDS_X(X%whoami),&
&                              Bp_index=PAR_IND_VAL_BANDS_X(X%whoami),&
&                              CLEAN_UP=.TRUE.)
   !
   if (iq==1) call PARALLEL_WF_index(COMM=PAR_COM_DIPOLES)
   if (iq> 1) call PARALLEL_WF_index(COMM=PAR_COM_Q_A2A)
   !
   if (WF_buffered_IO) call WF_load(WF_buffer,0,1,X%ib,(/1,Xk%nibz/),space='B',title='-BUFFER')
   !
   ! TDDFT setup
   !
   call TDDFT_do_X_W_typs(iq,X,wv)
   !
   ! ALDA (only once) 
   !
   if (l_alda_fxc.and..not.allocated(FXC)) then
     !
     call TDDFT_ALDA_G_space(Xen,Xk)
     !
   endif
   !
   if (iq>1) then
#if defined _LU
     if(nel_cond>0._SP) call warning("Luminescence only at q=0")
#endif
     if (.not.PAR_IND_Q%element_1D(iq)) cycle
   endif
   !
   ! Check if this q is compatible with the user defined direction in chartesian coordinates
   ! and if an additional RL vectors must be added
   !
   i_G_shift=O_select_q_and_G(iq,q,X,Q_plus_G_pt,Q_plus_G_sq_modulus)
   if (i_G_shift<0) cycle
   !
   ! In TDDFT with BS based kernel eps0 is non-sense
   ! as shifted of the K diagonal
   !
   l_skip_non_int_eps=l_bs_fxc
   !
   ! Arrays to be written in the o. files
   !
   allocate(Epsilon_ii(wv%n_freqs,2))
#if defined _LU
   allocate(Luminescence(wv%n_freqs,2))
#endif
   allocate(EEL(wv%n_freqs,2))
   allocate(Alpha(wv%n_freqs,2))
   if (l_bs_fxc) then
     allocate(X_fxc(wv%n_freqs))
     X_fxc=cZERO
   endif
   !
   ! X_mat allocation
   !
   call X_alloc('X',(/X%ng,X%ng,wv%n_freqs/))
   !
#if defined _LU
   if(nel_cond>0._SP) allocate(Lum_mat(wv%n_freqs))
#endif
   !
   ! Frequencies (AFTER TDDFT SETUP!)
   !
   call FREQUENCIES_setup(wv)
   !
   ! Check if EELS can be evaluated
   !
   eval_eels= O_eels(wv%p,wv%n_freqs,.TRUE.,X%ordering)
   !
   if (eval_alpha) eval_alpha=eval_eels
   !
   ! OutPut files...
   !
   if(.not.l_rpa_IP) call X_setup_file_names(iq,'inv',trim(FXC_type),'dyson',ig=i_G_shift)
   if(     l_rpa_IP) call X_setup_file_names(iq,'ip','','',ig=i_G_shift)
   !
   ! ... open ...
   !
   call of_open_close(eps_file_name,'ot')
#if defined _LU
   if(nel_cond/=0._SP.and.iq==1) then
     call of_open_close(lum_file_name,'ot')
   else
     lum_file_name=' '
   endif
#endif
   if (eval_eels)       call of_open_close(eel_file_name,'ot')
   if (.not.eval_eels)  eel_file_name=' '
   if (eval_alpha)      call of_open_close(alpha_file_name,'ot')
   if (.not.eval_alpha) alpha_file_name=' '
   if (l_bs_fxc)        call of_open_close(fxc_file_name,'ot')
   !
   ! Initial Messages
   !
   call X_write_q_plus_G(iq,Q_plus_G_pt,ig=i_G_shift)
   !
   ! Fxc descriptions
   !
   if (l_bs_fxc) then
     call X_write_descriptions(FXC_n_descs,FXC_description)
     call msg('o eps_q eel_q alpha','#',' TDDFT|Fxc size             :'//trim(intc(FXC_n_g_corr)),INDENT=0)    
     call msg('o eps_q eel_q alpha','#','      |Hartree size         :'//trim(intc(X%ng)),INDENT=0)    
     call msg('o eps_q eel_q alpha','#','      |Ordering             :'//trim(X%ordering),INDENT=0)    
     !
     ! Fxc file titles
     !
     call X_setup_headers('q^2Fxc')
     call msg('o fxc','#',(/headers(1),headers(3),headers(2)/),INDENT=0,USE_TABS=.true.)    
     call msg('o fxc','#')
   endif
   !
   ! BZ Double Grid
   !
   if (use_X_DbGd) then
#if defined _LU
     if(nel_cond>0._SP) call error("Double-grid not implemented yet in luminescence!")
#endif
     call msg('o eps_q eel_q fxc alpha lum','#')
     call msg('o eps_q eel_q fxc alpha','# BZ Energy DbGd points:',BZ_DbGd_tot_nkpts,INDENT=0)
   endif
   !
   if (iq==1) call PP_redux_wait
   if (iq> 1) call PP_redux_wait(COMM=PAR_COM_Q_A2A%COMM)
   !
   call of_open_close(eps_file_name)
   call of_open_close(eel_file_name)
   call of_open_close(alpha_file_name)
   call of_open_close(fxc_file_name)
#if defined _LU
   call of_open_close(lum_file_name)
#endif
   !
   ! e Table
   ! 1:e0     2:e     ==> Epsilon_ii(iw,1:2)
   ! 1:eel0   2:eel   ==> EEL(iw,1:2)
   ! 1:alpha0 6:alpha ==> Alpha(iw,1:2)
   !
   Epsilon_ii=cZERO
   EEL       =cZERO
   Alpha     =cZERO
#if defined _LU
   Luminescence =cZERO
#endif
   !
   call X_os(X_mat,iq,Xen,Xk,wv,X)     
   !
   ! Without LF eps
   !
   Epsilon_ii(:,1)=1.0_SP-X_mat(i_G_shift,i_G_shift,:)*4.0_SP*pi/Q_plus_G_sq_modulus
   !
   ! X Dyson equation solver
   !
#if defined _LU
   if(nel_cond>0._SP) then
     Luminescence(:,1)=Lum_mat(:)*4.0_SP*pi/Q_plus_G_sq_modulus
   endif
#endif
   !
   if(l_rpa_IP) then
     Epsilon_ii(:,2)=Epsilon_ii(:,1)
#if defined _LU
    if(iq==1) Luminescence(:,2)=Luminescence(:,1)
#endif
   else
     call X_s(iq,X,wv,(/1,wv%n_freqs/))
     !
     Epsilon_ii(:,2)=1._SP/(X_mat(i_G_shift,i_G_shift,:)*bare_qpg(iq,i_G_shift)**2/Q_plus_G_sq_modulus+1._SP)
     !
   endif
   !
   call of_open_close(eps_file_name,'oa')
   call of_open_close(eel_file_name,'oa')
   call of_open_close(alpha_file_name,'oa')
#if defined _LU
   call of_open_close(lum_file_name,'oa')
#endif
   !
   ! Unfortunately some of the variables need in this second bunch of messages is setup only in X_os
   !
   call X_write_messages_before_headers(iq,associated(Xen%GreenF),X%Vnl_included,X%ordering)
   !
   ! Titles 
   !
   n_output=5
   if(l_rpa_IP.or.l_skip_non_int_eps) n_output=3
   call msg('o eps_q eel_q fxc alpha lum','#')
   call X_setup_headers('EPS')
   call msg('o eps_q',  '#',headers(:n_output),INDENT=0,USE_TABS=.true.)    
   call X_setup_headers('EEL')
   call msg('o eel_q',  '#',headers(:n_output),INDENT=0,USE_TABS=.true.)    
   call X_setup_headers('ALPHA')
   call msg('o alpha','#',headers(:n_output),INDENT=0,USE_TABS=.true.)    
   call msg('o eps_q eel_q alpha','#')
#if defined _LU
   call X_setup_headers('PL')
   call msg('o lum','#',headers(:n_output),INDENT=0,USE_TABS=.true.)    
   call msg('o lum','#')
#endif
   !
   do iw=1,wv%n_freqs
     !
     ! Eps
     !
     output_data=(/real(wv%p(iw))*HA2EV,aimag(Epsilon_ii(iw,2)),real(Epsilon_ii(iw,2)),&
&                  aimag(Epsilon_ii(iw,1)),real(Epsilon_ii(iw,1))/)
     call msg('o eps_q','',output_data(:n_output),INDENT=-2,USE_TABS=.true.)
     !
   enddo
   !
#if defined _LU
   if(nel_cond>0._SP) then
     !  
     ! Luminescence
     !
     do iw=1,wv%n_freqs
       !
       output_data(:n_output)=(/real(wv%p(iw))*HA2EV,aimag(Luminescence(iw,2)),aimag(Luminescence(iw,1))/)
       call msg('o lum','',output_data(:n_output),INDENT=-2,USE_TABS=.true.)
       !
     enddo
     !
   endif
#endif
   !
   call of_open_close(eps_file_name)
   call of_open_close(eel_file_name)
   call of_open_close(alpha_file_name)
#if defined _LU
   call of_open_close(lum_file_name)
#endif
   !
   if (eval_eels) then 
     !
     call of_open_close(eel_file_name,'oa')
     call of_open_close(alpha_file_name,'oa')
     !
     eval_eels= O_eels(wv%p,wv%n_freqs,.TRUE.,X%ordering,Epsilon_ii(:,1),EEL(:,1))
     if(     l_rpa_IP) EEL(:,2) = EEL(:,1)
     if(.not.l_rpa_IP) eval_eels= O_eels(wv%p,wv%n_freqs,.FALSE.,X%ordering,Epsilon_ii(:,2),EEL(:,2))
     !
     if (eval_alpha) then
       !
       ! alpha = -eps_2_alpha X(1,1) / |q|^2    
       !       =  (1 -eps_M^-1) eps_2_alpha/4/pi
       !       =  (1 +eels    ) eps_2_alpha/4/pi  
       !
       Alpha(:,1)=(1._SP+EEL(:,1))/4._SP/pi*eps_2_alpha
       if(     l_rpa_IP) Alpha(:,2)= Alpha(:,1)
       if(.not.l_rpa_IP) Alpha(:,2)=(1._SP+EEL(:,2))/4._SP/pi*eps_2_alpha
       !
     endif
     !
     do iw=1,wv%n_freqs
       !
       ! EEL
       !
       output_data=(/real(wv%p(iw))*HA2EV,aimag(EEL(iw,2)),real(EEL(iw,2)),&
&                    aimag(EEL(iw,1)),real(EEL(iw,1))/)
       call msg('o eel_q','',output_data(:n_output),INDENT=-2,USE_TABS=.true.)
       !
       ! Alpha
       !
       output_data=(/real(wv%p(iw))*HA2EV,aimag(Alpha(iw,2)),real(Alpha(iw,2)),&
&                    aimag(Alpha(iw,1)),real(Alpha(iw,1))/)
       !
       call msg('o alpha','',output_data(:n_output),INDENT=-2,USE_TABS=.true.)
     enddo
     !
     call of_open_close(eel_file_name)
     call of_open_close(alpha_file_name)
     !
   endif
   !
   ! TDDFT Kernel output
   !
   if (l_bs_fxc) then
     if (iq==1) call PP_redux_wait(X_fxc)
     if (iq> 1) call PP_redux_wait(X_fxc,COMM=PAR_COM_Q_A2A%COMM)
     call of_open_close(fxc_file_name,'oa')
     do iw=1,wv%n_freqs
       call msg('o fxc','',(/real(wv%p(iw))*HA2EV,real(X_fxc(iw)*q_norm(iq)**2),&
&                           aimag(X_fxc(iw)*q_norm(iq)**2)/),INDENT=-2,USE_TABS=.true.)
     enddo
     call of_open_close(fxc_file_name)
   endif
   !
   ! CLEAN (each q)
   !
   call X_alloc('X')
#if defined _LU
   if(nel_cond>0._SP) deallocate(Lum_mat)
#endif
   !
   deallocate(Epsilon_ii,EEL,Alpha)
#if defined _LU
   deallocate(Luminescence)
#endif
   !
   call FREQUENCIES_reset(wv,"all")
   !
   if (allocated(X_fxc)) deallocate(X_fxc)
   !
 enddo
 !
 ! CLEAN
 !
 call X_alloc('DIP_projected')
 call WF_free(WF)
 call PP_redux_wait
 call set_real_printed_length()
 if (l_bs_fxc.and.allocated(FXC)) then
   deallocate(FXC,FXC_K_diagonal)
   call mem_est("FXC FXC_K_diagonal")
 endif
 !
end subroutine
