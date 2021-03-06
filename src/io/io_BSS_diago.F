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
integer function io_BSS_diago(iq,ID,BS_H_dim,bsE,bsRl,bsRr,BsE_corr,bsR_kerr,bsR_pl)
 !
 use pars,          ONLY:SP,schlen,IP
 use BS,            ONLY:BS_identifier,BS_K_dim
 use BS_solvers,    ONLY:BSS_q0,BSS_write_eig_2_db,BSS_eh_table,BS_mat
 use IO_m,          ONLY:io_connect,io_disconnect,io_sec,&
&                        io_elemental,io_status,io_bulk,&
&                        io_header,write_is_on,read_is_on
 use electrons,     ONLY:n_sp_pol,E_SOC_nbands
 !
 implicit none
 !
 integer              :: iq,ID,BS_H_dim
 complex(SP)          :: bsE(BS_H_dim),bsRl(BS_H_dim),bsRr(BS_H_dim)
 real(SP)   ,pointer  :: BsE_corr(:,:),bsR_pl(:,:)
 complex(SP),pointer  :: bsR_kerr(:)
 !
 ! Work Space
 !
 integer          :: i1
 real(SP)         :: V_disk(4,BS_H_dim)
 character(schlen):: db_name
 !
 write (db_name,'(a,i2.2)') 'BS_diago_Q',iq
 !
 io_BSS_diago=io_connect(desc=trim(db_name),type=2,ID=ID)
 if (io_BSS_diago/=0) goto 1
 !
 if (any((/io_sec(ID,:)==1/))) then
   !
   ! As this DB must respect the BS ideentifier I only need to
   ! check the K QP corrections
   !
   io_BSS_diago=io_header(ID,XC_KIND="K_E force")
   !
   call io_elemental(ID,VAR="PARS",VAR_SZ=5,MENU=0)
   !
   call io_elemental(ID,VAR=&
&       " BSK Identifier                  :",I0=BS_identifier,CHECK=.TRUE.,OP=(/"=="/))
   call io_elemental(ID,VAR=&
&       " Excitonic eigenstates included  :",L0=BSS_write_eig_2_db,CHECK=.true.,OP=(/"=="/))
   call io_elemental(ID,VAR=&
&       " Field direction                 :",R1=BSS_q0,CHECK=.true.,OP=(/"==","==","=="/))
   call io_elemental(ID,VAR="",VAR_SZ=0,MENU=1)
   !
   ! header return
   !
   if (io_BSS_diago/=0) goto 1
   !
   io_BSS_diago=io_status(ID)
   if (io_BSS_diago/=0) goto 1
 endif
 !
 if (any((/io_sec(ID,:)==2/))) then
   !
   call io_bulk(ID,'BS_Energies',VAR_SZ=(/2,BS_H_dim/))
   if (write_is_on(ID)) V_disk(1,:)=real(bsE(:))
   if (write_is_on(ID)) V_disk(2,:)=aimag(bsE(:))
   call io_bulk(ID,R2=V_disk(:2,:))
   if (read_is_on(ID)) bsE(:)=cmplx(V_disk(1,:),V_disk(2,:),SP)
   !
   if(E_SOC_nbands/=0) then
     call io_bulk(ID,'BS_Energies_SOC_corr',VAR_SZ=(/2/n_sp_pol,BS_H_dim/))
     call io_bulk(ID,R2=BsE_corr)
   endif
   !
   call io_bulk(ID,'BS_Residuals',VAR_SZ=(/4,BS_H_dim/))
   if (write_is_on(ID)) V_disk(1,:)=real(bsRl(:))
   if (write_is_on(ID)) V_disk(2,:)=aimag(bsRl(:))
   if (write_is_on(ID)) V_disk(3,:)=real(bsRr(:))
   if (write_is_on(ID)) V_disk(4,:)=aimag(bsRr(:))
   call io_bulk(ID,R2=V_disk)
   if (read_is_on(ID)) bsRl(:)=cmplx(V_disk(1,:),V_disk(2,:),SP)
   if (read_is_on(ID)) bsRr(:)=cmplx(V_disk(3,:),V_disk(4,:),SP)
   !
   if(associated(bsR_pl)) then
     call io_bulk(ID,'BS_PL_Residuals',VAR_SZ=(/2,BS_H_dim/))
     call io_bulk(ID,R2=bsR_pl)
   endif
   !
 endif
 !
 if (any((/io_sec(ID,:)==3/))) then
   ! 
   ! If not switched on skip this section
   !
   if (.not.BSS_write_eig_2_db) then
     io_BSS_diago=-1
     goto 1
   endif
   !
   ! BS_eh_table
   !
   call io_bulk(ID,'BS_TABLE',VAR_SZ=(/BS_K_dim,3+n_sp_pol-1/))
   call io_bulk(ID,I2=BSS_eh_table(:BS_K_dim,:))
   !
   ! Eigenstates (resonant only matrix)
   !
   call io_bulk(ID,'BS_EIGENSTATES',VAR_SZ=(/2,BS_H_dim,BS_H_dim/))
   !
   do i1=1,BS_H_dim
     !
     if (write_is_on(ID)) V_disk(1,:)=real(BS_mat(:,i1))
     if (write_is_on(ID)) V_disk(2,:)=aimag(BS_mat(:,i1))
     !
     call io_bulk(ID,R2=V_disk(:2,:),IPOS=(/1,1,i1/))
     !
     if (read_is_on(ID)) BS_mat(:,i1)=cmplx(V_disk(1,:),V_disk(2,:),SP)
     !
   enddo
   !
 endif
 !
1 call io_disconnect(ID)
 !
end function
