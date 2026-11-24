-- ****
-- T65(b) core. In an effort to merge and maintain bug fixes ....
--
-- See list of changes in T65 top file (T65.vhd)...
--
-- ****
-- 65xx compatible microprocessor core
--
-- FPGAARCADE SVN: $Id: T65_Pack.vhd 1234 2015-02-28 20:14:50Z wolfgang.scherr $
--
-- Copyright (c) 2002...2015
--               Daniel Wallner (jesus <at> opencores <dot> org)
--               Mike Johnson   (mikej <at> fpgaarcade <dot> com)
--               Wolfgang Scherr (WoS <at> pin4 <dot> at>
--               Morten Leikvoll ()
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author(s), but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-- Limitations :
--   See in T65 top file (T65.vhd)...

library IEEE;
use IEEE.std_logic_1164.all;

package T65_Pack is

  constant Flag_C : integer := 0;
  constant Flag_Z : integer := 1;
  constant Flag_I : integer := 2;
  constant Flag_D : integer := 3;
  constant Flag_B : integer := 4;
  constant Flag_1 : integer := 5;
  constant Flag_V : integer := 6;
  constant Flag_N : integer := 7;

  subtype T_Lcycle is std_logic_vector(2 downto 0);
  constant Cycle_sync :T_Lcycle:="000";
  constant Cycle_1    :T_Lcycle:="001";
  constant Cycle_2    :T_Lcycle:="010";
  constant Cycle_3    :T_Lcycle:="011";
  constant Cycle_4    :T_Lcycle:="100";
  constant Cycle_5    :T_Lcycle:="101";
  constant Cycle_6    :T_Lcycle:="110";
  constant Cycle_7    :T_Lcycle:="111";

  function CycleNext(c:T_Lcycle) return T_Lcycle;

  type T_Set_BusA_To is
  (
    Set_BusA_To_DI,
    Set_BusA_To_ABC,
    Set_BusA_To_X,
    Set_BusA_To_Y,
    Set_BusA_To_S,
    Set_BusA_To_P,
    Set_BusA_To_DA,
    Set_BusA_To_DAO,
    Set_BusA_To_DAX,
    Set_BusA_To_AAX,
    Set_BusA_To_DONTCARE
  );
  
  type T_Set_Addr_To is
  (
    Set_Addr_To_PBR,
    Set_Addr_To_SP,
    Set_Addr_To_ZPG,
    Set_Addr_To_BA
  );
  
  type T_Write_Data is
  (
    Write_Data_DL,
    Write_Data_ABC,
    Write_Data_X,
    Write_Data_Y,
    Write_Data_S,
    Write_Data_P,
    Write_Data_PCL,
    Write_Data_PCH,
    Write_Data_AX,
    Write_Data_AXB,
    Write_Data_XB,
    Write_Data_YB,
    Write_Data_DONTCARE
  );
  
  type T_ALU_OP is
  (
    ALU_OP_OR,
    ALU_OP_AND,
    ALU_OP_EOR,
    ALU_OP_ADC,
    ALU_OP_EQ1, -- Pass BusA without changing flags.
    ALU_OP_EQ2, -- Pass BusA and update N/Z.
    ALU_OP_CMP,
    ALU_OP_SBC,
    ALU_OP_ASL,
    ALU_OP_ROL,
    ALU_OP_LSR,
    ALU_OP_ROR,
    ALU_OP_BIT,
    ALU_OP_DEC,
    ALU_OP_INC,
    ALU_OP_ARR,
    ALU_OP_ANC,
    ALU_OP_SAX,
    ALU_OP_XAA
  );

  type T_t65_dbg is record
    I     : std_logic_vector(7 downto 0); -- instruction
    A     : std_logic_vector(7 downto 0); -- A reg
    X     : std_logic_vector(7 downto 0); -- X reg
    Y     : std_logic_vector(7 downto 0); -- Y reg
    S     : std_logic_vector(7 downto 0); -- stack pointer
    P     : std_logic_vector(7 downto 0); -- processor flags
  end record;

end;

package body T65_Pack is

  function CycleNext(c:T_Lcycle) return T_Lcycle is
  begin
    case(c) is
    when Cycle_sync=>
      return Cycle_1;
    when Cycle_1=>
      return Cycle_2;
    when Cycle_2=>
      return Cycle_3;
    when Cycle_3=>
      return Cycle_4;
    when Cycle_4=>
      return Cycle_5;
    when Cycle_5=>
      return Cycle_6;
    when Cycle_6=>
      return Cycle_7;
    when Cycle_7=>
      return Cycle_sync;
    when others=>
      return Cycle_sync;
    end case;
  end CycleNext;

end T65_Pack;
