!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM DS
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
subroutine K_inversion_engine(what,iw_2start,iw_2do,px,W,Lo,Lo_dim,Lo_n_loop,do_it_full)
 !
 use pars,           ONLY:SP,cZERO
 use parallel_m,     ONLY:PP_indexes,myid
 use frequency,      ONLY:w_samp
 use X_m,            ONLY:Epsilon_ii,global_gauge
 use LIVE_t,         ONLY:live_timing
 use R_lattice,      ONLY:q_norm
 use wrapper,        ONLY:Vstar_dot_V,M_by_V
 use BS,             ONLY:BS_H_dim
 use BS_solvers,     ONLY:BS_mat,Co_factor,K_INV_EPS,BSS_dipoles,Co_factor
 !
 implicit none
 !
 character(3)     :: what
 integer          :: iw_2start,iw_2do,Lo_dim,Lo_n_loop
 type(PP_indexes) :: px
 type(w_samp)     :: W
 complex(SP)      :: Lo(BS_H_dim,W%n_freqs,Lo_dim)
 logical          :: do_it_full
 !
 ! Work Space
 !
 integer      :: i2,iw,i_L
 character(1) :: Gr
 complex(SP)              :: gauge_factor
 complex(SP), allocatable :: Mm1(:,:)
 integer,        external :: EPS_via_perturbative_inversion
 !
 if (do_it_full) then
   allocate(Mm1(BS_H_dim,BS_H_dim))
   Mm1=cZERO
 endif
 !
 do i2=1,iw_2do
   !
   iw=i2+iw_2start-1
   !
   if (trim(global_gauge)=='length'  ) gauge_factor=-Co_factor/q_norm(1)**2
   if (trim(global_gauge)=='velocity') gauge_factor=-Co_factor/ W%p(iw) **2
   !
   ! The parallel loop is controlled in the manin body loop 
   ! when a full inversion is performed
   !
   if (.not.do_it_full) then
     !
     if(.not.px%element_1D(iw)) then
       K_INV_EPS%err(iw)=0
       cycle
     endif
     !
     if (K_INV_EPS%err(iw)/=0) then
       K_INV_EPS%err(iw)=EPS_via_perturbative_inversion(BS_H_dim,Lo_dim,Lo_n_loop,BSS_dipoles,gauge_factor,&
&                                                       Epsilon_ii(iw,2),Lo(:,iw,:),BS_mat)
     endif
     !
   else
     !
     do i_L=1,Lo_n_loop
       !
       if (i_L==1) Gr="r"
       if (i_L==2) Gr="a"
       !
       call K_inversion_do_it_full(Lo(:,iw,i_L),Mm1,Gr)
       !
       if (what=="EPS".or.what=="any") then
         call EPS_compose(i_L)
         K_INV_EPS%err(iw)=0
       endif
       !
       !
     enddo
     !
   endif
   !       
   if (.not.do_it_full) call live_timing(steps=1)
   !
 enddo
 !
 if (do_it_full) then
   deallocate(Mm1)
 else
   call live_timing()
 endif
 !
 contains
   !
   !
   subroutine EPS_compose(i_L_)
     integer     :: i_L_
     complex(SP) :: V(BS_H_dim)
     if(i_L_==1) then
       call M_by_V('n',BS_H_dim,Mm1,BSS_dipoles,V)
       Epsilon_ii(iw,2)=gauge_factor*Vstar_dot_V(BS_H_dim,BSS_dipoles,V)
     else if(i_L_==2) then
       call M_by_V('n',BS_H_dim,Mm1,conjg(BSS_dipoles),V)
       Epsilon_ii(iw,2)=Epsilon_ii(iw,2)+gauge_factor*Vstar_dot_V(BS_H_dim,conjg(BSS_dipoles),V)
     endif
   end subroutine
   !
end subroutine K_inversion_engine
