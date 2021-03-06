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
module interfaces
 !
 implicit none
 !
 interface
   !
   subroutine SCATTERING_GW_kinematics(i_q_bz,i_m,I,k,q,TABLE,E,N,G0,Ek,Ekmq,E_diff)
     use pars,                ONLY:SP
     use electrons,           ONLY:levels
     use R_lattice,           ONLY:bz_samp
     use QP_m,                ONLY:QP_table
     use collision,           ONLY:elemental_collision
     integer,       intent(in) ::i_q_bz,i_m
     integer,       intent(in) ::TABLE(:)
     type(elemental_collision) ::I
     type(bz_samp)             ::k,q
     type(levels),  OPTIONAL   ::E
     integer,       OPTIONAL   ::N,G0
     real(SP),      OPTIONAL   ::Ek,Ekmq,E_diff
   end subroutine
   !
   subroutine el_density_and_current(E,k,rho,J,bands,force_spatial_inversion)
     use pars,           ONLY:SP
     use electrons,      ONLY:levels
     use R_lattice,      ONLY:bz_samp
     use FFT_m,          ONLY:fft_size
     implicit none
     type(bz_samp)::k
     type(levels) ::E       
     real(SP), optional             ::rho(fft_size)
     real(SP), optional             ::J(fft_size,3)
     integer,  optional, intent(in) ::bands(2)
     logical,  optional, intent(in) ::force_spatial_inversion
   end subroutine el_density_and_current
   !
   subroutine el_density_of_states(Xk,Xen,dos_E,dos_broadening,dos_bands,dos_value,l_DbGd,WF_fac)
     use pars,           ONLY:SP
     use electrons,      ONLY:levels
     use R_lattice,      ONLY:bz_samp 
     use electrons,      ONLY:n_spin
     implicit none
     type(bz_samp), intent(in)  :: Xk
     type(levels),  intent(in)  :: Xen
     real(SP),      intent(in)  :: dos_E,dos_broadening
     integer,       intent(in)  :: dos_bands(2)
     real(SP),      intent(out) :: dos_value(n_spin)
     logical,       intent(in)  :: l_DbGd
     real(SP), optional, intent(in) :: WF_fac(dos_bands(1):dos_bands(2),Xk%nibz,2)
   end subroutine el_density_of_states
   !
   integer function io_COLLISIONS(i_qp,ID,COLL)
     use collision,  ONLY:COLLISIONS_element
     integer, intent(inout)             ::ID
     integer, intent(in)                ::i_qp
     type(COLLISIONS_element), optional :: COLL
   end function
   !
   integer function eval_G_minus_G(iG,iGo,COMM)
     use parallel_m,      ONLY:MPI_comm
     implicit none
     integer :: iG,iGo
     type(MPI_comm), optional :: COMM
   end function
   !
   subroutine WF_load(WF,iG_max,iGo_max,bands_to_load,kpts_to_load,&
&                     spins_to_load,space,title,impose_free_and_alloc,&
&                     force_WFo,keep_states_to_load)
     use wave_func,       ONLY:WAVEs
     integer :: iG_max,iGo_max,bands_to_load(2),kpts_to_load(2)
     type(WAVEs)           :: WF
     integer,     optional :: spins_to_load(2)
     character(*),optional :: space
     character(*),optional :: title
     logical     ,optional :: impose_free_and_alloc
     logical     ,optional :: force_WFo
     logical     ,optional :: keep_states_to_load
   end subroutine
   !
   subroutine PARALLEL_WF_index(COMM)
     use parallel_m,      ONLY:MPI_comm
     type(MPI_comm), optional :: COMM
   end subroutine
   !
   subroutine PARALLEL_global_indexes(E,Xk,q,ENVIRONMENT,X,RESET)
     use X_m,           ONLY:X_t
     use electrons,     ONLY:levels
     use R_lattice,     ONLY:bz_samp
     implicit none
     type(levels)             ::E
     type(bz_samp)            ::Xk,q
     character(*)             ::ENVIRONMENT
     type(X_t),       optional::X
     logical,         optional::RESET
   end subroutine
   !
   subroutine PARALLEL_live_message(WHAT,ENVIRONMENT,LOADED,TOTAL,LOADED_r,TOTAL_r,NCPU)
     use pars,           ONLY:SP
     character(*)          :: WHAT
     character(*),optional :: ENVIRONMENT
     integer,     optional :: LOADED,TOTAL,NCPU
     real(SP),    optional :: LOADED_r,TOTAL_r
   end subroutine
   !
   subroutine PARALLEL_WF_distribute(B_index,Bp_index,K_index,B_and_K_index,&
&                                    QP_index,PLASMA_index,Bm_index,CLEAN_UP)
     !
     use parallel_m,      ONLY:PP_indexes
     !
     implicit none
     !
     type(PP_indexes),    optional :: K_index
     type(PP_indexes),    optional :: B_index
     type(PP_indexes),    optional :: Bp_index
     type(PP_indexes),    optional :: B_and_K_index
     type(PP_indexes),    optional :: QP_index
     type(PP_indexes),    optional :: PLASMA_index
     type(PP_indexes),    optional :: Bm_index
     logical, intent(in), optional :: CLEAN_UP
     !
   end subroutine 
   !
   subroutine OCCUPATIONS_Gaps(E,E_g_dir,E_g_ind,N_f,N_m,I_dir)
     use pars,          ONLY: SP
     use electrons,     ONLY:levels,n_sp_pol
     type(levels)       :: E
     real(SP), optional :: E_g_dir(n_sp_pol,2) ! min - max
     real(SP), optional :: E_g_ind(n_sp_pol,2) ! min - max
     integer , optional :: N_f(n_sp_pol)
     integer , optional :: N_m(n_sp_pol)
     integer , optional :: I_dir(2)
   end subroutine 
   !
   subroutine K_diago_compute_epsilon(iq,W,BS_E,BS_R_left,BS_R_right,BS_E_SOC_corr,BS_R_kerr,BS_R_PL)
     use BS,            ONLY:BS_H_dim
     use pars,          ONLY:SP
     use frequency,     ONLY:w_samp
     type(w_samp),intent(in)  :: W
     integer,     intent(in)  :: iq
     complex(SP), intent(in)  :: BS_E(BS_H_dim)
     complex(SP), intent(in)  :: BS_R_left(BS_H_dim),BS_R_right(BS_H_dim)
     real(SP),    pointer     :: BS_E_SOC_corr(:,:)
     complex(SP), pointer     :: BS_R_kerr(:)
     real(SP),    pointer     :: BS_R_PL(:,:)
   end subroutine
   !
   subroutine PARALLEL_assign_chains_and_COMMs(n_elements,ROLE,COMM_index_1,COMM_index_2,COMM_index_3,&
&                                              COMM_index_4,COMM_A2A_1,COMM_A2A_2,COMM_A2A_3)
     use parallel_m,    ONLY:MPI_comm
     integer                 :: n_elements
     character(*)            :: ROLE(:)
     type(MPI_comm)          :: COMM_index_1
     type(MPI_comm),optional :: COMM_index_2
     type(MPI_comm),optional :: COMM_index_3
     type(MPI_comm),optional :: COMM_index_4
     type(MPI_comm),optional :: COMM_A2A_1
     type(MPI_comm),optional :: COMM_A2A_2
     type(MPI_comm),optional :: COMM_A2A_3
   end subroutine
   !
   subroutine PARALLEL_index(px,uplim,low_range,COMM,CONSECUTIVE,ORDERED,NO_EMPTIES,MASK)
     use parallel_m, ONLY:PP_indexes,MPI_COMM
     type(PP_indexes)       ::px
     integer                ::uplim(:)
     integer, optional      ::low_range(:)
     type(MPI_COMM),optional::COMM
     logical,       optional::CONSECUTIVE
     logical,       optional::ORDERED
     logical,       optional::NO_EMPTIES
     logical,       optional::MASK(:)
   end subroutine
   !
   subroutine NL_average_operator(O_VALUE,V_VALUE,O_REAL,O_MATRIX,V_MATRIX,PV_MATRIX,V_bands,k,en,TRANS,nK_mem)
     !
     use pars,           ONLY:SP
     use nl_optics,      ONLY:NL_bands
     use R_lattice,      ONLY:bz_samp
     use QP_m,           ONLY:QP_nk
     use electrons,      ONLY:n_sp_pol,n_spin,levels
     use FFT_m,          ONLY:fft_size
     !
     implicit none
     !
     type(bz_samp), intent(in) :: k
     type(levels),  intent(in) :: en
     complex(SP),   intent(in) :: V_bands(NL_bands(2),en%nbf,QP_nk, n_sp_pol)
     integer,       intent(in) :: nK_mem
     !
     ! Optionals
     !
     complex(SP),     optional, intent(out):: O_VALUE,V_VALUE(3)
     complex(SP),     optional, intent(in) :: PV_MATRIX(3,NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),nK_mem,n_sp_pol)
     complex(SP),     optional, intent(in) ::  V_MATRIX(3,NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),nK_mem,n_sp_pol)
     complex(SP),     optional, intent(in) ::  O_MATRIX(  NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),nK_mem,n_sp_pol)
     real(SP),        optional, intent(in) :: O_REAL(fft_size,n_spin)
     logical,         optional, intent(in) :: TRANS
     !
   end subroutine
   !
 end interface
 !
end module
