export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      datos_personales: {
        Row: {
          persona_id: string
          nombre_dni: string | null
          fecha_nacimiento: string | null
          estado_civil: string | null
          direccion: string | null
          celular: string | null
          entidad_bancaria: string | null
          numero_cuenta: string | null
          grado_instruccion: string | null
          hijos_menores: boolean | null
          foto_dni_url: string | null
          foto_personal_url: string | null
          foto_profesional_url: string | null
          emergencia_nombre: string | null
          emergencia_vinculo: string | null
          emergencia_telefono: string | null
          discapacidad: boolean | null
          discapacidad_conadis: string | null
          // Agregada a mano el 2026-08-08 (la creó la 0198), por el mismo
          // motivo que los campos de personas: `supabase gen types` en esta
          // máquina reescribe el archivo entero con otro formato. Es el código
          // con el que la AFP identifica la cuenta individual de la persona;
          // obligatorio en el T-Registro para afiliados al sistema privado, y
          // null para ONP y jubilados, que no tienen cuenta individual.
          cuspp: string | null
          actualizado_por: string | null
          actualizado_at: string
        }
        Insert: {
          persona_id: string
          nombre_dni?: string | null
          fecha_nacimiento?: string | null
          estado_civil?: string | null
          direccion?: string | null
          celular?: string | null
          entidad_bancaria?: string | null
          numero_cuenta?: string | null
          grado_instruccion?: string | null
          hijos_menores?: boolean | null
          foto_dni_url?: string | null
          foto_personal_url?: string | null
          foto_profesional_url?: string | null
          emergencia_nombre?: string | null
          emergencia_vinculo?: string | null
          emergencia_telefono?: string | null
          discapacidad?: boolean | null
          discapacidad_conadis?: string | null
          cuspp?: string | null
          actualizado_por?: string | null
          actualizado_at?: string
        }
        Update: {
          persona_id?: string
          nombre_dni?: string | null
          fecha_nacimiento?: string | null
          estado_civil?: string | null
          direccion?: string | null
          celular?: string | null
          entidad_bancaria?: string | null
          numero_cuenta?: string | null
          grado_instruccion?: string | null
          hijos_menores?: boolean | null
          foto_dni_url?: string | null
          foto_personal_url?: string | null
          foto_profesional_url?: string | null
          emergencia_nombre?: string | null
          emergencia_vinculo?: string | null
          emergencia_telefono?: string | null
          discapacidad?: boolean | null
          discapacidad_conadis?: string | null
          cuspp?: string | null
          actualizado_por?: string | null
          actualizado_at?: string
        }
        Relationships: []
      }
      // La tabla de la 0074, que no estaba en los tipos: por eso la pantalla de
      // disciplina no podía leer los cargos archivados. Escrita a mano como el
      // resto — `supabase gen types` no corre en esta máquina.
      expediente_adjuntos: {
        Row: {
          id: string
          documento_id: string
          storage_path: string
          tipo: string
          nota: string | null
          subido_por: string | null
          subido_at: string
        }
        Insert: {
          id?: string
          documento_id: string
          storage_path: string
          tipo: string
          nota?: string | null
          subido_por?: string | null
          subido_at?: string
        }
        Update: {
          nota?: string | null
        }
        Relationships: []
      }
      expediente_disciplinario: {
        Row: {
          id: string
          correlativo: string | null
          persona_id: string
          tipo_causal: string
          nivel: string
          estado: string
          periodo_desde: string | null
          periodo_hasta: string | null
          hechos: Json
          suspension_dias: number | null
          suspension_desde: string | null
          suspension_hasta: string | null
          doc_previo_id: string | null
          firmante_id: string | null
          firmado_at: string | null
          medio_entrega: string | null
          entregado_at: string | null
          observacion: string | null
          creado_por: string
          creado_at: string
        }
        Insert: {
          id?: string
          correlativo?: string | null
          persona_id: string
          tipo_causal: string
          nivel: string
          estado?: string
          periodo_desde?: string | null
          periodo_hasta?: string | null
          hechos?: Json
          suspension_dias?: number | null
          suspension_desde?: string | null
          suspension_hasta?: string | null
          doc_previo_id?: string | null
          firmante_id?: string | null
          firmado_at?: string | null
          medio_entrega?: string | null
          entregado_at?: string | null
          observacion?: string | null
          creado_por: string
          creado_at?: string
        }
        Update: {
          id?: string
          correlativo?: string | null
          persona_id?: string
          tipo_causal?: string
          nivel?: string
          estado?: string
          periodo_desde?: string | null
          periodo_hasta?: string | null
          hechos?: Json
          suspension_dias?: number | null
          suspension_desde?: string | null
          suspension_hasta?: string | null
          doc_previo_id?: string | null
          firmante_id?: string | null
          firmado_at?: string | null
          medio_entrega?: string | null
          entregado_at?: string | null
          observacion?: string | null
          creado_por?: string
          creado_at?: string
        }
        Relationships: []
      }
      alertas: {
        Row: {
          canal: string
          created_at: string
          enviado_at: string | null
          estado: string
          id: string
          leido_at: string | null
          payload: Json
          persona_id: string | null
          tipo: string
        }
        Insert: {
          canal: string
          created_at?: string
          enviado_at?: string | null
          estado?: string
          id?: string
          leido_at?: string | null
          payload?: Json
          persona_id?: string | null
          tipo: string
        }
        Update: {
          canal?: string
          created_at?: string
          enviado_at?: string | null
          estado?: string
          id?: string
          leido_at?: string | null
          payload?: Json
          persona_id?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "alertas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      configuracion: {
        Row: {
          clave: string
          descripcion: string | null
          valor: Json
        }
        Insert: {
          clave: string
          descripcion?: string | null
          valor: Json
        }
        Update: {
          clave?: string
          descripcion?: string | null
          valor?: Json
        }
        Relationships: []
      }
      correcciones_auditoria: {
        Row: {
          campo_modificado: string
          corregido_at: string
          corregido_por: string
          id: string
          marcaje_id: string | null
          motivo: string
          persona_id: string
          valor_anterior: string | null
          valor_nuevo: string | null
        }
        Insert: {
          campo_modificado: string
          corregido_at?: string
          corregido_por: string
          id?: string
          marcaje_id?: string | null
          motivo: string
          persona_id: string
          valor_anterior?: string | null
          valor_nuevo?: string | null
        }
        Update: {
          campo_modificado?: string
          corregido_at?: string
          corregido_por?: string
          id?: string
          marcaje_id?: string | null
          motivo?: string
          persona_id?: string
          valor_anterior?: string | null
          valor_nuevo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "correcciones_auditoria_corregido_por_fkey"
            columns: ["corregido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_marcaje_id_fkey"
            columns: ["marcaje_id"]
            isOneToOne: false
            referencedRelation: "marcajes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      google_sheets_sync_queue: {
        Row: {
          created_at: string
          estado: string
          id: string
          intentos: number
          jornada_id: string | null
          last_error: string | null
          marcaje_id: string | null
          payload: Json
        }
        Insert: {
          created_at?: string
          estado?: string
          id?: string
          intentos?: number
          jornada_id?: string | null
          last_error?: string | null
          marcaje_id?: string | null
          payload: Json
        }
        Update: {
          created_at?: string
          estado?: string
          id?: string
          intentos?: number
          jornada_id?: string | null
          last_error?: string | null
          marcaje_id?: string | null
          payload?: Json
        }
        Relationships: [
          {
            foreignKeyName: "google_sheets_sync_queue_jornada_id_fkey"
            columns: ["jornada_id"]
            isOneToOne: false
            referencedRelation: "jornadas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "google_sheets_sync_queue_marcaje_id_fkey"
            columns: ["marcaje_id"]
            isOneToOne: false
            referencedRelation: "marcajes"
            referencedColumns: ["id"]
          },
        ]
      }
      horarios_asignados: {
        Row: {
          almuerzo_max_minutos: number
          almuerzo_min_minutos: number
          created_at: string
          dias_laborables: number[]
          hora_entrada: string
          hora_salida: string
          horario_por_dia: Json | null
          horas_semana_objetivo: number
          id: string
          persona_id: string
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          almuerzo_max_minutos?: number
          almuerzo_min_minutos?: number
          created_at?: string
          dias_laborables?: number[]
          hora_entrada: string
          hora_salida: string
          horario_por_dia?: Json | null
          horas_semana_objetivo?: number
          id?: string
          persona_id: string
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          almuerzo_max_minutos?: number
          almuerzo_min_minutos?: number
          created_at?: string
          dias_laborables?: number[]
          hora_entrada?: string
          hora_salida?: string
          horario_por_dia?: Json | null
          horas_semana_objetivo?: number
          id?: string
          persona_id?: string
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "horarios_asignados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      jornadas: {
        Row: {
          entrada_ts: string | null
          estado: Database["public"]["Enums"]["estado_jornada"]
          fecha: string
          horas_extra_detectadas: number
          horas_trabajadas: number | null
          id: string
          minutos_salida_temprana: number | null
          minutos_tarde: number | null
          persona_id: string
          salida_final_ts: string | null
          sede_id: string | null
          tiene_salida_no_retornada: boolean
          updated_at: string
        }
        Insert: {
          entrada_ts?: string | null
          estado?: Database["public"]["Enums"]["estado_jornada"]
          fecha: string
          horas_extra_detectadas?: number
          horas_trabajadas?: number | null
          id?: string
          minutos_salida_temprana?: number | null
          minutos_tarde?: number | null
          persona_id: string
          salida_final_ts?: string | null
          sede_id?: string | null
          tiene_salida_no_retornada?: boolean
          updated_at?: string
        }
        Update: {
          entrada_ts?: string | null
          estado?: Database["public"]["Enums"]["estado_jornada"]
          fecha?: string
          horas_extra_detectadas?: number
          horas_trabajadas?: number | null
          id?: string
          minutos_salida_temprana?: number | null
          minutos_tarde?: number | null
          persona_id?: string
          salida_final_ts?: string | null
          sede_id?: string | null
          tiene_salida_no_retornada?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "jornadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jornadas_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      marcajes: {
        Row: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        Insert: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          client_uuid: string
          estado_revision?: Database["public"]["Enums"]["estado_revision"]
          id?: string
          motivo_otro?: string | null
          origen?: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at?: string
          terminal_id?: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        Update: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          client_uuid?: string
          estado_revision?: Database["public"]["Enums"]["estado_revision"]
          id?: string
          motivo_otro?: string | null
          origen?: Database["public"]["Enums"]["origen_marca"]
          persona_id?: string
          sede_id?: string
          server_received_at?: string
          terminal_id?: string | null
          timestamp_marca?: string
          tipo?: Database["public"]["Enums"]["tipo_marca"]
        }
        Relationships: [
          {
            foreignKeyName: "marcajes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_terminal_id_fkey"
            columns: ["terminal_id"]
            isOneToOne: false
            referencedRelation: "terminales"
            referencedColumns: ["id"]
          },
        ]
      }
      // Agregada a mano el 2026-08-03: la pantalla de Equipo lee el arranque del
      // periodo abierto para proponerlo como vigencia del salario. `supabase gen
      // types` no corre en esta Mac, así que los tipos se mantienen a mano.
      periodos_planilla: {
        Row: {
          id: string
          fecha_ini: string
          fecha_fin: string
          estado: string
          pagado_at: string | null
          creado_por: string | null
          created_at: string
        }
        Insert: {
          id?: string
          fecha_ini: string
          fecha_fin: string
          estado?: string
          pagado_at?: string | null
          creado_por?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          fecha_ini?: string
          fecha_fin?: string
          estado?: string
          pagado_at?: string | null
          creado_por?: string | null
          created_at?: string
        }
        Relationships: []
      }
      // Agregada a mano junto con la migración 0125, por el mismo motivo que
      // parametros_laborales: `supabase gen types` no corre en esta Mac.
      derechohabientes: {
        Row: {
          id: string
          persona_id: string
          nombres: string
          apellidos: string
          documento: string | null
          fecha_nacimiento: string | null
          vinculo: string
          essalud: boolean
          vida_ley: boolean
          vigente_hasta: string | null
          nota: string | null
          registrado_por: string | null
          created_at: string
        }
        Insert: {
          id?: string
          persona_id: string
          nombres: string
          apellidos: string
          documento?: string | null
          fecha_nacimiento?: string | null
          vinculo: string
          essalud?: boolean
          vida_ley?: boolean
          vigente_hasta?: string | null
          nota?: string | null
          registrado_por?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          persona_id?: string
          nombres?: string
          apellidos?: string
          documento?: string | null
          fecha_nacimiento?: string | null
          vinculo?: string
          essalud?: boolean
          vida_ley?: boolean
          vigente_hasta?: string | null
          nota?: string | null
          registrado_por?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "derechohabientes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      personas: {
        Row: {
          apellidos: string
          auth_user_id: string | null
          created_at: string
          documento: string | null
          email: string | null
          en_planilla: boolean
          estado: string
          sueldo_base_legal: number | null
          sueldo_fijo: boolean
          // Agregada a mano el 2026-08-08 (la creó la 0187), por el mismo motivo
          // que sueldo_base_legal arriba: `supabase gen types` en esta máquina
          // reescribe el archivo entero con otro formato. Es la marca de personal
          // de dirección del art. 5 del D.S. 007-2002-TR — quien la tiene queda
          // fuera de la jornada máxima y no genera sobretiempo. NO es lo mismo
          // que sueldo_fijo (condición de pago) ni que rol (permiso del sistema).
          personal_direccion: boolean
          fecha_estado_cambio: string | null
          // Agregada a mano el 2026-08-05 (la creó la 0144), por el mismo motivo
          // que tipo_vinculo más abajo: `supabase gen types` no corre en esta
          // máquina. Es la fecha PREVISTA de término del contrato a plazo fijo —
          // null es lo normal (contrato indefinido) y NO es lo mismo que el cese.
          fecha_fin_contrato: string | null
          fecha_ingreso: string
          funcion: string
          id: string
          nombres: string
          pin_hash: string
          regimen_pension: string | null
          rol: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
          // Agregada a mano el 2026-08-04 (la creó la 0085), por el mismo motivo
          // que parametros_laborales más abajo: `supabase gen types` no corre en
          // esta máquina. Al regenerar se produce sola y este comentario sobra.
          // `en_planilla` de arriba es su columna DERIVADA: false para 'rxh' y
          // 'no_trabajador'.
          tipo_vinculo: string
          updated_at: string
          visible_todas_sedes: boolean
        }
        Insert: {
          apellidos: string
          auth_user_id?: string | null
          created_at?: string
          documento?: string | null
          email?: string | null
          en_planilla?: boolean
          estado?: string
          sueldo_base_legal?: number | null
          sueldo_fijo?: boolean
          personal_direccion?: boolean
          fecha_estado_cambio?: string | null
          fecha_fin_contrato?: string | null
          fecha_ingreso?: string
          funcion?: string
          id?: string
          nombres: string
          pin_hash: string
          regimen_pension?: string | null
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
          tipo_vinculo?: string
          updated_at?: string
          visible_todas_sedes?: boolean
        }
        Update: {
          apellidos?: string
          auth_user_id?: string | null
          created_at?: string
          documento?: string | null
          email?: string | null
          en_planilla?: boolean
          estado?: string
          sueldo_base_legal?: number | null
          sueldo_fijo?: boolean
          personal_direccion?: boolean
          fecha_estado_cambio?: string | null
          fecha_fin_contrato?: string | null
          fecha_ingreso?: string
          funcion?: string
          id?: string
          nombres?: string
          pin_hash?: string
          regimen_pension?: string | null
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id?: string
          tipo_vinculo?: string
          updated_at?: string
          visible_todas_sedes?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "personas_sede_base_id_fkey"
            columns: ["sede_base_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      push_tokens: {
        Row: {
          activo: boolean
          expo_push_token: string
          id: string
          last_seen_at: string
          persona_id: string
          plataforma: string
        }
        Insert: {
          activo?: boolean
          expo_push_token: string
          id?: string
          last_seen_at?: string
          persona_id: string
          plataforma: string
        }
        Update: {
          activo?: boolean
          expo_push_token?: string
          id?: string
          last_seen_at?: string
          persona_id?: string
          plataforma?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_tokens_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      sedes: {
        Row: {
          activa: boolean
          codigo: string
          id: string
          nombre: string
          tipo: string
        }
        Insert: {
          activa?: boolean
          codigo: string
          id?: string
          nombre: string
          tipo?: string
        }
        Update: {
          activa?: boolean
          codigo?: string
          id?: string
          nombre?: string
          tipo?: string
        }
        Relationships: []
      }
      tarifas_hora: {
        Row: {
          creado_por: string | null
          created_at: string
          id: string
          nota: string | null
          persona_id: string
          tarifa_hora_soles: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          creado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id: string
          tarifa_hora_soles: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          creado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id?: string
          tarifa_hora_soles?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tarifas_hora_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tarifas_hora_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      terminales: {
        Row: {
          activo: boolean
          auth_user_id: string | null
          id: string
          nombre_dispositivo: string
          requiere_pin: boolean
          sede_id: string
          ultimo_visto_at: string | null
        }
        Insert: {
          activo?: boolean
          auth_user_id?: string | null
          id?: string
          nombre_dispositivo: string
          requiere_pin?: boolean
          sede_id: string
          ultimo_visto_at?: string | null
        }
        Update: {
          activo?: boolean
          auth_user_id?: string | null
          id?: string
          nombre_dispositivo?: string
          requiere_pin?: boolean
          sede_id?: string
          ultimo_visto_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "terminales_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      turnos: {
        Row: {
          es_descanso: boolean
          fecha: string
          hora_entrada: string | null
          hora_salida: string | null
          id: string
          origen: string
          persona_id: string
        }
        Insert: {
          es_descanso?: boolean
          fecha: string
          hora_entrada?: string | null
          hora_salida?: string | null
          id?: string
          origen?: string
          persona_id: string
        }
        Update: {
          es_descanso?: boolean
          fecha?: string
          hora_entrada?: string | null
          hora_salida?: string | null
          id?: string
          origen?: string
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "turnos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      tardanzas_justificadas: {
        Row: {
          creado_at: string
          creado_por: string
          fecha: string
          id: string
          motivo: string
          observacion: string | null
          persona_id: string
        }
        Insert: {
          creado_at?: string
          creado_por: string
          fecha: string
          id?: string
          motivo: string
          observacion?: string | null
          persona_id: string
        }
        Update: {
          creado_at?: string
          creado_por?: string
          fecha?: string
          id?: string
          motivo?: string
          observacion?: string | null
          persona_id?: string
        }
        Relationships: []
      }
      justificaciones_asistencia: {
        Row: {
          creado_at: string
          creado_por: string
          fecha: string
          id: string
          motivo: string
          observacion: string | null
          persona_id: string
        }
        Insert: {
          creado_at?: string
          creado_por: string
          fecha: string
          id?: string
          motivo: string
          observacion?: string | null
          persona_id: string
        }
        Update: {
          creado_at?: string
          creado_por?: string
          fecha?: string
          id?: string
          motivo?: string
          observacion?: string | null
          persona_id?: string
        }
        Relationships: []
      }
      incidencias_aceptadas: {
        Row: {
          aceptado_at: string
          aceptado_por: string
          fecha: string
          id: string
          nota: string | null
          persona_id: string
          tipo: string
        }
        Insert: {
          aceptado_at?: string
          aceptado_por: string
          fecha: string
          id?: string
          nota?: string | null
          persona_id: string
          tipo: string
        }
        Update: {
          aceptado_at?: string
          aceptado_por?: string
          fecha?: string
          id?: string
          nota?: string | null
          persona_id?: string
          tipo?: string
        }
        Relationships: []
      }
      // Agregada a mano el 2026-08-01 junto con las migraciones 0116 y 0118, por el
      // mismo motivo que fn_set_tipo_vinculo: `supabase gen types` no corre en esta
      // máquina. Al regenerar se produce sola y este comentario se puede borrar.
      parametros_laborales: {
        Row: {
          id: string
          clave: string
          valor: number
          vigente_desde: string
          vigente_hasta: string | null
          sustento: string | null
          created_at: string
        }
        Insert: {
          id?: string
          clave: string
          valor: number
          vigente_desde: string
          vigente_hasta?: string | null
          sustento?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          clave?: string
          valor?: number
          vigente_desde?: string
          vigente_hasta?: string | null
          sustento?: string | null
          created_at?: string
        }
        Relationships: []
      }
      // Añadida a mano, migración 0208 — ver la nota en las funciones.
      documentos_tipos: {
        Row: {
          codigo: string
          nombre: string
          orden: number
          requiere_acuse: boolean
          activo: boolean
        }
        Insert: {
          codigo: string
          nombre: string
          orden?: number
          requiere_acuse?: boolean
          activo?: boolean
        }
        Update: {
          codigo?: string
          nombre?: string
          orden?: number
          requiere_acuse?: boolean
          activo?: boolean
        }
        Relationships: []
      }
      feriados: {
        Row: {
          fecha: string
          nombre: string
        }
        Insert: {
          fecha: string
          nombre: string
        }
        Update: {
          fecha?: string
          nombre?: string
        }
        Relationships: []
      }
      feriados_descanso_sustitutorio: {
        Row: {
          acta_ref: string | null
          created_at: string
          estado: string
          fecha_descanso_sustitutorio: string
          fecha_feriado: string
          id: string
          otorgado_por: string | null
          persona_id: string
          updated_at: string
        }
        Insert: {
          acta_ref?: string | null
          created_at?: string
          estado?: string
          fecha_descanso_sustitutorio: string
          fecha_feriado: string
          id?: string
          otorgado_por?: string | null
          persona_id: string
          updated_at?: string
        }
        Update: {
          acta_ref?: string | null
          created_at?: string
          estado?: string
          fecha_descanso_sustitutorio?: string
          fecha_feriado?: string
          id?: string
          otorgado_por?: string | null
          persona_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      vacaciones: {
        Row: {
          creado_at: string
          creado_por: string
          fecha_fin: string
          fecha_inicio: string
          id: string
          observacion: string | null
          persona_id: string
        }
        Insert: {
          creado_at?: string
          creado_por: string
          fecha_fin: string
          fecha_inicio: string
          id?: string
          observacion?: string | null
          persona_id: string
        }
        Update: {
          creado_at?: string
          creado_por?: string
          fecha_fin?: string
          fecha_inicio?: string
          id?: string
          observacion?: string | null
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vacaciones_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vacaciones_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      metas_cobertura: {
        Row: {
          dia_semana: number
          meta: number
          meta_encargadas: number
          meta_tarde: number
          sede_id: string
          updated_at: string
        }
        Insert: {
          dia_semana: number
          meta?: number
          meta_encargadas?: number
          meta_tarde?: number
          sede_id: string
          updated_at?: string
        }
        Update: {
          dia_semana?: number
          meta?: number
          meta_encargadas?: number
          meta_tarde?: number
          sede_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "metas_cobertura_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      asignaciones_salario: {
        Row: {
          asignado_por: string | null
          created_at: string
          id: string
          nota: string | null
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          asignado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          asignado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id?: string
          rango?: string
          salario_mensual_soles?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asignaciones_salario_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_salario_asignado_por_fkey"
            columns: ["asignado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      fn_agregar_marcaje: {
        Args: {
          p_motivo: string
          p_motivo_otro?: string
          p_persona_id: string
          p_tipo: Database["public"]["Enums"]["tipo_marca"]
          p_ts: string
        }
        Returns: {
          client_uuid: string
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_auto_cierre: { Args: never; Returns: number }
      fn_corregir_marcaje: {
        Args: { p_marcaje_id: string; p_motivo: string; p_nuevo_ts: string }
        Returns: {
          client_uuid: string
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_eliminar_marcaje: {
        Args: { p_marcaje_id: string; p_motivo: string }
        Returns: undefined
      }
      fn_es_admin_o_lider: { Args: never; Returns: boolean }
      fn_exigir_admin: { Args: never; Returns: string }
      fn_persona_actual_id: { Args: never; Returns: string }
      fn_quitar_horario: {
        Args: { p_desde: string; p_persona_id: string }
        Returns: undefined
      }
      fn_recalcular_jornada: {
        Args: { p_fecha: string; p_persona_id: string }
        Returns: undefined
      }
      fn_registrar_marcaje: {
        Args: {
          p_client_uuid: string
          p_motivo_otro?: string
          p_origen?: Database["public"]["Enums"]["origen_marca"]
          p_persona_id: string
          p_sede_id?: string
          p_terminal_id?: string
          p_timestamp_cliente: string
          p_tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        Returns: {
          client_uuid: string
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_rol_actual: {
        Args: never
        Returns: Database["public"]["Enums"]["rol_usuario"]
      }
      fn_sede_actual_persona: { Args: never; Returns: string }
      fn_sede_actual_terminal: { Args: never; Returns: string }
      fn_set_horario: {
        Args: {
          p_almuerzo_max?: number
          p_almuerzo_min?: number
          p_dias_laborables?: number[]
          p_hora_entrada: string
          p_hora_salida: string
          p_persona_id: string
          p_vigente_desde: string
        }
        Returns: undefined
      }
      fn_set_horario_semanal: {
        Args: {
          p_horario: Json
          p_persona_id: string
          p_vigente_desde: string
        }
        Returns: undefined
      }
      fn_set_turno: {
        Args: {
          p_fecha: string
          p_hora_entrada: string
          p_hora_salida?: string | null
          p_persona_id: string
        }
        Returns: undefined
      }
      fn_set_descanso: {
        Args: { p_fecha: string; p_persona_id: string }
        Returns: undefined
      }
      fn_quitar_turno: {
        Args: { p_fecha: string; p_persona_id: string }
        Returns: undefined
      }
      fn_set_vacaciones: {
        Args: {
          p_fecha_fin: string
          p_fecha_inicio: string
          p_observacion?: string | null
          p_persona_id: string
        }
        Returns: string
      }
      fn_quitar_vacaciones: {
        Args: { p_id: string }
        Returns: undefined
      }
      fn_otorgar_descanso_sustitutorio: {
        Args: {
          p_persona_id: string
          p_fecha_feriado: string
          p_fecha_descanso: string
          p_estado?: string
          p_acta_ref?: string | null
        }
        Returns: string
      }
      fn_quitar_descanso_sustitutorio: {
        Args: { p_id: string }
        Returns: undefined
      }
      fn_feriados_laborados: {
        Args: { p_desde: string; p_hasta: string }
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          fecha_feriado: string
          feriado_nombre: string
          horas: number
          sobretasa: number
          dcs_id: string
          fecha_descanso: string
          estado: string
          acta_ref: string
        }[]
      }
      fn_subir_acta_descanso: {
        Args: { p_referencia: string; p_dataurl: string | null; p_nombre?: string | null }
        Returns: string
      }
      fn_actas_descanso: {
        Args: Record<string, never>
        Returns: {
          referencia: string
          archivo_nombre: string | null
          tiene_archivo: boolean
          peso_kb: number
          actualizado: string
          registros: number
        }[]
      }
      fn_acta_descanso: {
        Args: { p_referencia: string }
        Returns: string | null
      }
      // ── mig. 0175 · el acta pasó a guardarse en el almacén ──────────────
      // Añadidas a mano y no regenerando el archivo entero: `supabase gen
      // types` con el CLI de hoy reescribe 3.000 líneas por cambios de
      // formato, y eso es otro cambio — uno que merece su propio commit y su
      // propia revisión, no colarse dentro de un arreglo de subida de papeles.
      fn_registrar_acta_descanso: {
        Args: { p_referencia: string; p_path: string; p_nombre?: string | null }
        Returns: string
      }
      fn_acta_descanso_ubicacion: {
        Args: { p_referencia: string }
        Returns: {
          storage_path: string | null
          dataurl: string | null
        }[]
      }
      fn_aceptar_incidencia: {
        Args: { p_persona_id: string; p_fecha: string; p_tipo: string; p_nota?: string | null }
        Returns: undefined
      }
      fn_quitar_aceptacion: {
        Args: { p_persona_id: string; p_fecha: string; p_tipo: string }
        Returns: undefined
      }
      fn_faltas: {
        Args: { p_desde: string; p_hasta: string }
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          fecha: string
          justificada: boolean
          motivo: string | null
        }[]
      }
      fn_set_justificacion: {
        Args: { p_persona_id: string; p_fecha: string; p_motivo: string; p_observacion?: string | null }
        Returns: undefined
      }
      fn_quitar_justificacion: {
        Args: { p_persona_id: string; p_fecha: string }
        Returns: undefined
      }
      fn_levantar_tardanza: {
        Args: { p_persona_id: string; p_fecha: string; p_motivo: string; p_observacion?: string | null }
        Returns: undefined
      }
      fn_quitar_levantamiento: {
        Args: { p_persona_id: string; p_fecha: string }
        Returns: undefined
      }
      fn_tardanzas_resumen: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          tardanzas_mes: number
          umbral: string
          ultima_fecha: string | null
        }[]
      }
      fn_dias_por_revisar: {
        Args: { p_limite?: number }
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          fecha: string
          marcas: number
        }[]
      }
      fn_faltas_resumen: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          consecutivas: number
          en_30: number
          en_180: number
          nivel: string
        }[]
      }
      fn_expediente_generar_tardanza: {
        Args: { p_persona_id: string }
        Returns: string
      }
      fn_expediente_generar_falta: {
        Args: { p_persona_id: string }
        Returns: string
      }
      fn_expediente_firmar: {
        Args: { p_id: string; p_firmante_id?: string | null }
        Returns: string
      }
      fn_firmantes_disponibles: {
        Args: Record<PropertyKey, never>
        Returns: { id: string; nombre: string }[]
      }
      // ── Migración 0074 (rescate de la copia de iCloud) ──────────────────────
      // El cargo que se imprime en un memo sale del rol de quien lo suscribe.
      fn_cargo_de_rol: {
        Args: { p_rol: string }
        Returns: string | null
      }
      // Quiénes pueden suscribir ESTE documento (más estricta que
      // fn_firmantes_disponibles: filtra por nivel y sede del documento).
      fn_expediente_firmantes: {
        Args: { p_id: string }
        Returns: { persona_id: string; nombre: string; cargo: string; tiene_firma: boolean }[]
      }
      fn_expediente_adjuntar: {
        Args: {
          p_documento_id: string
          p_path: string
          p_tipo?: string
          p_fecha_entrega?: string | null
          p_nota?: string | null
        }
        Returns: string
      }
      fn_expediente_puede_adjuntar: {
        Args: { p_path: string }
        Returns: boolean
      }
      // ── Migración 0075 (rescate) ────────────────────────────────────────────
      // Los días de suspensión son días LABORABLES de esa persona, no de calendario.
      fn_es_dia_laborable: {
        Args: { p_persona_id: string; p_fecha: string }
        Returns: boolean
      }
      fn_dias_suspension: {
        Args: { p_persona_id: string; p_desde: string; p_dias: number }
        Returns: { fecha: string }[]
      }
      fn_expediente_set_suspension: {
        Args: { p_id: string; p_dias: number; p_desde: string }
        Returns: { fecha: string }[]
      }
      fn_expediente_entregar: {
        Args: { p_id: string; p_medio: string; p_fecha?: string }
        Returns: undefined
      }
      fn_expediente_editar_borrador: {
        Args: {
          p_id: string
          p_suspension_dias?: number | null
          p_suspension_desde?: string | null
          p_suspension_hasta?: string | null
          p_observacion?: string | null
          p_hechos?: Json
        }
        Returns: undefined
      }
      fn_expediente_anular: {
        Args: { p_id: string; p_motivo: string }
        Returns: undefined
      }
      fn_expediente_reabrir: {
        Args: { p_id: string }
        Returns: undefined
      }
      // Firma de la 0149, escrita a mano: `supabase gen types` no corre en esta
      // máquina («Failed to end the connection on error»). Ya no viajan ni
      // `p_monto` (lo calcula la base) ni `p_cobertura_pct` (es 75 fijo).
      fn_educacion_registrar: {
        Args: {
          p_persona_id: string
          p_institucion: string
          p_costo_declarado: number
          p_beneficiario: string
          p_vigente_desde: string
          p_vigente_hasta: string
          p_beneficiario_nombre?: string | null
          p_comprobante_url?: string | null
          p_nota?: string | null
          p_id?: string | null
          p_motivo?: string | null
        }
        Returns: string
      }
      fn_educacion_cerrar: {
        Args: { p_id: string; p_hasta: string; p_motivo?: string | null }
        Returns: undefined
      }
      fn_educacion_monto: {
        Args: { p_persona_id: string; p_costo: number }
        Returns: number
      }
      fn_educacion_por_atender: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      // 0154, escrita a mano como el resto: `supabase gen types` no corre acá.
      // 0157, escritas a mano: `supabase gen types` no corre en esta máquina.
      // 0164/0167/0169, escritas a mano: `supabase gen types` no corre acá.
      fn_liquidacion: {
        Args: { p_persona_id: string; p_fecha_cese?: string | null }
        Returns: Json
      }
      fn_liquidacion_pagar: {
        Args: { p_persona_id: string; p_nota?: string | null }
        Returns: Json
      }
      fn_liquidacion_diferencias: {
        Args: { p_persona_id: string }
        Returns: {
          concepto: string
          pagado: number
          ahora: number
          diferencia: number
        }[]
      }
      // Agregada a mano el 2026-08-10 (la creó la 0210), por el mismo motivo
      // que el cuspp y personal_direccion de arriba: `supabase gen types` en
      // esta máquina reescribe el archivo entero con otro formato y se lleva por
      // delante estas anotaciones. Devuelve un objeto indexado por persona_id
      // —no una lista— para que la pantalla de Planilla busque por clave en vez
      // de recorrerla por cada fila. `{}` cuando no hay nada que decir, y
      // también cuando quien pregunta no es admin ni líder.
      fn_liquidaciones_del_periodo: {
        Args: { p_periodo_id: string }
        Returns: Json
      }
      fn_liquidaciones_pendientes: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          persona: string
          sede: string
          fecha_ingreso: string | null
          fecha_cese: string
          vence_el: string
          dias_restantes: number
          vencido: boolean
          total: number
          pagada: boolean
          descuadra: boolean
        }[]
      }
      fn_avisos_vinculo: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          persona: string
          sede: string
          tipo_vinculo: string
          fecha_ingreso: string
          dias: number
          cumple_el_mes: string
          ya_devenga: boolean
          aviso: string
        }[]
      }
      fn_documento_registrar: {
        Args: {
          p_tipo: string
          p_fecha_firma: string
          p_persona_id?: string | null
          p_ruta_declarada?: string | null
          p_monto_declarado?: number | null
          p_anio?: number | null
          p_es_negativa?: boolean | null
          p_nota?: string | null
          p_storage_path?: string | null
          p_id?: string | null
        }
        Returns: string
      }
      fn_documento_anular: {
        Args: { p_id: string; p_motivo: string }
        Returns: undefined
      }
      fn_documentos_tablero: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          persona: string
          sede: string
          fecha_ingreso: string | null
          ruta_id: string | null
          ruta_firmada_el: string | null
          ruta_monto: number | null
          ruta_negativa: boolean
          ruta_desfasada: boolean
          bono_id: string | null
          bono_anio: number | null
          estado: string
        }[]
      }
      fn_documentos_estado_politica: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string | null
          cargada: boolean
          fecha_firma: string | null
          primer_pago: string | null
          llego_tarde: boolean
          storage_path: string | null
        }[]
      }
      fn_documentos_listar: {
        Args: { p_persona_id?: string | null }
        Returns: {
          id: string
          alcance: string
          persona_id: string | null
          persona: string
          tipo: string
          fecha_firma: string
          ruta_declarada: string | null
          monto_declarado: number | null
          anio: number | null
          es_negativa: boolean
          storage_path: string | null
          nota: string | null
          registrado_por: string
          anulado_at: string | null
          anulado_motivo: string | null
          vigente: boolean
        }[]
      }
      fn_educacion_limite_comprobante: {
        Args: Record<PropertyKey, never>
        Returns: {
          limite_bytes: number
          tipos: string[]
        }[]
      }
      fn_educacion_puede_ver: {
        Args: { p_path: string }
        Returns: boolean
      }
      fn_educacion_listar: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string
          persona_id: string
          persona: string
          sede: string
          rango: string
          monto: number
          institucion: string
          costo_declarado: number
          cobertura_pct: number
          beneficiario: string
          beneficiario_nombre: string | null
          comprobante_url: string | null
          vigente_desde: string
          vigente_hasta: string
          nota: string | null
          registrada_por: string | null
          dias_para_vencer: number
          semaforo: string
          paga: boolean
        }[]
      }
      fn_educacion_candidatos: {
        Args: Record<PropertyKey, never>
        Returns: {
          persona_id: string
          persona: string
          sede: string
          rango: string
          tope: number | null
          ya_tiene: boolean
        }[]
      }
      fn_set_datos_personales: {
        Args: {
          p_persona_id: string
          p_nombre_dni?: string | null
          p_fecha_nacimiento?: string | null
          p_estado_civil?: string | null
          p_direccion?: string | null
          p_celular?: string | null
          p_entidad_bancaria?: string | null
          p_numero_cuenta?: string | null
          p_grado_instruccion?: string | null
          p_hijos_menores?: boolean | null
          p_foto_dni_url?: string | null
          p_foto_personal_url?: string | null
          p_foto_profesional_url?: string | null
          p_emergencia_nombre?: string | null
          p_emergencia_vinculo?: string | null
          p_emergencia_telefono?: string | null
          p_discapacidad?: boolean | null
          p_discapacidad_conadis?: string | null
          p_cuspp?: string | null
        }
        Returns: undefined
      }
      // La 0198. Cambia el correo SOLO si la persona no tiene cuenta de acceso:
      // con cuenta creada su correo es su login, y la función lo rechaza.
      fn_set_email: {
        Args: { p_persona_id: string; p_email: string | null }
        Returns: undefined
      }
      fn_set_documento: {
        Args: { p_persona_id: string; p_documento: string; p_motivo: string }
        Returns: undefined
      }
      fn_set_regimen_pension: {
        Args: { p_persona_id: string; p_regimen: string | null }
        Returns: undefined
      }
      fn_set_derechohabiente: {
        Args: {
          p_id: string | null
          p_persona_id: string
          p_nombres: string
          p_apellidos: string
          p_vinculo: string
          p_documento?: string | null
          p_fecha_nacimiento?: string | null
          p_essalud?: boolean
          p_vida_ley?: boolean
          p_nota?: string | null
        }
        Returns: string
      }
      fn_cerrar_derechohabiente: {
        Args: { p_id: string; p_hasta?: string | null }
        Returns: undefined
      }
      fn_vacaciones_resumen: {
        Args: { p_as_of?: string }
        Returns: Json
      }
      fn_grati_cts_periodo: {
        Args: { p_periodo_id: string }
        Returns: Json
      }
      fn_set_meta_cobertura: {
        Args: { p_dia_semana: number; p_meta_manana: number; p_meta_tarde: number; p_sede_id: string }
        Returns: undefined
      }
      fn_set_meta_encargadas: {
        Args: { p_dia_semana: number; p_meta: number; p_sede_id: string }
        Returns: undefined
      }
      fn_siguiente_tipo_esperado: {
        Args: { p_fecha: string; p_persona_id: string }
        Returns: Database["public"]["Enums"]["tipo_marca"]
      }
      fn_verificar_corrector: {
        Args: { p_persona_objetivo: string }
        Returns: string
      }
      fn_set_salario: {
        Args: {
          p_nota?: string
          p_persona_id: string
          p_rango: string
          p_salario: number
          p_vigente_desde: string
        }
        Returns: undefined
      }
      fn_salarios_vigentes: {
        Args: never
        Returns: {
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
        }[]
      }
      fn_historial_salario: {
        Args: { p_persona_id: string }
        Returns: {
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta: string | null
          asignado_por: string | null
          nota: string | null
          created_at: string
        }[]
      }
      fn_personas_funciones: {
        Args: never
        Returns: Json
      }
      // Agregada a mano (migración 0182): `supabase gen types` no corre en esta
      // máquina («Failed to end the connection on error»), así que las entradas
      // nuevas se escriben acá marcadas hasta que vuelva a correr.
      fn_set_cargo: {
        Args: {
          p_persona_id: string
          p_cargo: string | null
        }
        Returns: undefined
      }
      fn_areas: {
        Args: never
        Returns: Json
      }
      fn_guardar_area: {
        Args: {
          p_codigo: string
          p_nombre: string
          p_operativa: boolean
          p_orden?: number
        }
        Returns: undefined
      }
      fn_area_activa: {
        Args: { p_activa: boolean; p_codigo: string }
        Returns: undefined
      }
      fn_guardar_sede: {
        Args: { p_codigo: string; p_nombre: string; p_tipo?: string | null }
        Returns: undefined
      }
      fn_sede_activa: {
        Args: { p_activa: boolean; p_codigo: string }
        Returns: undefined
      }
      fn_feriados: {
        Args: { p_anio: number }
        Returns: Json
      }
      fn_set_feriado: {
        Args: { p_fecha: string; p_nombre: string }
        Returns: undefined
      }
      fn_quitar_feriado: {
        Args: { p_fecha: string }
        Returns: undefined
      }
      fn_set_objetivos: {
        Args: {
          p_anio: number
          p_cumplidos: number
          p_mes: number
          p_persona_id: string
          p_total?: number
        }
        Returns: undefined
      }
      fn_set_sueldo_base_legal: {
        Args: { p_monto: number; p_persona_id: string }
        Returns: undefined
      }
      fn_set_rendimiento: {
        Args: {
          p_anio: number
          p_etiqueta_codigo?: string | null
          p_mes: number
          p_persona_id: string
          p_porcentaje: number
        }
        Returns: undefined
      }
      fn_quitar_rendimiento: {
        Args: { p_anio: number; p_mes: number; p_persona_id: string }
        Returns: undefined
      }
      fn_objetivos_checklist: {
        Args: { p_anio: number; p_mes: number; p_persona_id?: string }
        Returns: Json
      }
      fn_objetivos_resumen: {
        Args: { p_anio: number; p_mes: number }
        Returns: Json
      }
      fn_objetivo_agregar: {
        Args: {
          p_anio: number
          p_descripcion: string
          p_mes: number
          p_persona_id: string
        }
        Returns: Json
      }
      fn_objetivo_marcar: {
        Args: { p_cumplido: boolean; p_item_id: string }
        Returns: undefined
      }
      fn_objetivo_editar: {
        Args: { p_descripcion: string; p_item_id: string }
        Returns: undefined
      }
      fn_objetivo_eliminar: {
        Args: { p_item_id: string }
        Returns: undefined
      }
      fn_proyeccion_planilla: {
        Args: { p_anio: number; p_mes: number }
        Returns: Json
      }
      fn_periodos: {
        Args: never
        Returns: Json
      }
      fn_crear_periodo: {
        Args: { p_fecha_fin: string; p_fecha_ini?: string }
        Returns: Json
      }
      fn_periodo_pagado: {
        Args: { p_pagado: boolean; p_periodo_id: string }
        Returns: undefined
      }
      fn_eliminar_periodo: {
        Args: { p_periodo_id: string }
        Returns: undefined
      }
      fn_agregar_movimiento: {
        Args: {
          p_categoria?: string | null
          p_concepto: string
          p_monto: number
          p_periodo_id: string
          p_persona_id: string
          p_tipo: string
        }
        Returns: Json
      }
      fn_quitar_movimiento: {
        Args: { p_movimiento_id: string }
        Returns: undefined
      }
      fn_calcular_bono_puntualidad: {
        Args: { p_periodo_id: string }
        Returns: Json
      }
      fn_set_con_hijos: {
        Args: { p_con_hijos: boolean; p_persona_id: string }
        Returns: undefined
      }
      fn_set_encargada_piso: {
        Args: { p_persona_id: string; p_valor: boolean }
        Returns: undefined
      }
      // Agregada a mano el 2026-08-01 junto con la migración 0119, porque
      // `supabase gen types` no pudo regenerar el archivo en esta máquina (falla
      // con «Failed to end the connection on error», sin detalle). Se declara acá
      // para no dejar la llamada de equipo/page.tsx sin tipo y sumar un error más
      // a los que ya arrastra este archivo. Al regenerar, esta entrada se produce
      // sola y el comentario se puede borrar.
      fn_set_tipo_vinculo: {
        Args: { p_persona_id: string; p_tipo: string }
        Returns: undefined
      }
      fn_set_visible_todas_sedes: {
        Args: { p_persona_id: string; p_valor: boolean }
        Returns: undefined
      }
      // Agregada a mano el 2026-08-05 junto con la columna fecha_fin_contrato, por
      // el mismo motivo que fn_set_tipo_vinculo. `p_fecha` acepta null a propósito:
      // así es como se BORRA la fecha cuando el contrato se renueva.
      fn_set_fin_contrato: {
        Args: { p_persona_id: string; p_fecha: string | null; p_motivo?: string }
        Returns: undefined
      }
      // Las dos de la 0086 que ninguna pantalla llamaba hasta el 2026-08-06. El
      // `update` directo de `estado` que hacía Equipo violaba
      // `personas_cese_coherente` (comprobado contra el Postgres local): dar de
      // baja y reactivar fallaban las dos.
      fn_cesar_persona: {
        Args: { p_persona_id: string; p_fecha_cese: string; p_motivo: string; p_tipo_vinculo?: string | null }
        Returns: undefined
      }
      fn_reactivar_persona: {
        Args: { p_persona_id: string }
        Returns: undefined
      }
      // `dias_restantes` es negativo cuando la fecha ya pasó, y ese es justamente
      // el grupo que importa: alguien que ya no viene pero sigue figurando activo.
      fn_contratos_por_vencer: {
        Args: { p_dias?: number }
        Returns: {
          persona_id: string
          nombre: string
          sede: string
          fecha_fin_contrato: string
          dias_restantes: number
          ya_vencio: boolean
        }[]
      }
      fn_set_mi_firma: {
        Args: { p_dataurl: string | null }
        Returns: undefined
      }
      fn_firma_persona: {
        Args: { p_persona_id: string }
        Returns: string | null
      }
      fn_mi_firma: {
        Args: Record<string, never>
        Returns: string | null
      }
      // Agregadas a mano el 2026-08-04 junto con las migraciones 0140 y 0141, por
      // el mismo motivo que fn_set_tipo_vinculo: `supabase gen types` reescribe el
      // archivo entero y borra estas mismas entradas escritas a mano. Al regenerar
      // de verdad se producen solas y el comentario se puede borrar.
      fn_cuadro_categorias: {
        Args: Record<string, never>
        Returns: unknown
      }
      fn_set_categoria: {
        Args: {
          p_rango: string
          p_proposito: string | null
          p_funciones: string | null
          p_requisitos: string | null
          p_criterio: string | null
        }
        Returns: undefined
      }
      fn_publicar_politica_salarial: {
        Args: { p_documento: string; p_notas: string | null }
        Returns: number
      }
      fn_politica_salarial_vigente: {
        Args: Record<string, never>
        Returns: unknown
      }
      fn_acusar_politica_salarial: {
        Args: { p_nombre: string }
        Returns: unknown
      }
      fn_acuses_politica_salarial: {
        Args: Record<string, never>
        Returns: unknown
      }
      // ── Añadidas a mano, migración 0208 ──────────────────────────────────
      // Este archivo es GENERADO, pero regenerarlo con el CLI de hoy reordena
      // sus 4.400 líneas enteras, así que el repo lo evita a propósito (ver el
      // comentario de admin/disciplina). Estas cinco se agregan en su sitio
      // alfabético; el día que toque regenerar de verdad, saldrán solas.
      fn_publicar_documento: {
        Args: {
          p_tipo: string
          p_titulo: string
          p_documento: string
          p_vigente_desde?: string | null
          p_notas?: string | null
        }
        Returns: unknown
      }
      fn_acusar_documento: {
        Args: { p_documento_id: string; p_nombre_declarado: string }
        Returns: unknown
      }
      fn_registrar_acuse_papel: {
        Args: {
          p_documento_id: string
          p_persona_id: string
          p_path: string
          p_acusado_at?: string | null
          p_nota?: string | null
        }
        Returns: unknown
      }
      fn_documentos_vigentes: {
        Args: Record<string, never>
        Returns: unknown
      }
      fn_acuses_documento: {
        Args: { p_documento_id: string }
        Returns: unknown
      }
      fn_anular_marcaje: {
        Args: { p_marcaje_id: string; p_motivo: string }
        Returns: unknown
      }
      fn_reactivar_marcaje: {
        Args: { p_marcaje_id: string; p_motivo: string }
        Returns: unknown
      }
      fn_corregir_marca: {
        Args: {
          p_marcaje_id: string
          p_nuevo_tipo?: string
          p_nuevo_ts?: string
          p_motivo?: string
        }
        Returns: unknown
      }
      fn_confirmar_auto_cierre: {
        Args: { p_marcaje_id: string; p_motivo?: string }
        Returns: unknown
      }
      fn_dia_incoherente: {
        Args: { p_persona_id: string; p_fecha: string }
        Returns: boolean
      }
      fn_firma_de_memo: {
        Args: { p_doc_id: string }
        Returns: string | null
      }
      fn_revertir_pago: {
        Args: { p_periodo_id: string; p_motivo: string }
        Returns: undefined
      }
      fn_proyeccion_periodo: {
        Args: { p_periodo_id: string }
        Returns: Json
      }
      fn_simular_planilla: {
        Args: { p_fin: string; p_ini: string }
        Returns: Json
      }
      fn_ingresos: {
        Args: never
        Returns: Json
      }
      fn_set_fecha_ingreso: {
        Args: { p_fecha: string; p_persona_id: string }
        Returns: undefined
      }
      fn_provisiones: {
        Args: { p_as_of?: string }
        Returns: Json
      }
      fn_planilla_congelar: {
        Args: { p_periodo_id: string; p_origen: string; p_autor: string | null }
        Returns: number
      }
      fn_repagar_periodo: {
        Args: { p_periodo_id: string; p_motivo: string }
        Returns: Json
      }
      fn_registrar_ausencia: {
        Args: {
          p_persona_id: string
          p_tipo: string
          p_fecha_inicio: string
          p_fecha_fin: string
          p_motivo?: string | null
          p_doc_profesional?: string | null
          p_doc_colegiatura?: string | null
          p_doc_fecha?: string | null
        }
        Returns: string
      }
      fn_anular_ausencia: {
        Args: { p_id: string; p_motivo: string }
        Returns: undefined
      }
      fn_aprobar_ausencia: {
        Args: { p_id: string }
        Returns: undefined
      }
      fn_ausencias: {
        Args: { p_desde: string; p_hasta: string; p_persona_id?: string | null }
        Returns: {
          id: string
          persona_id: string
          nombre: string
          sede: string
          tipo: string
          tipo_nombre: string
          paga: boolean
          requiere_aprobacion: boolean
          fecha_inicio: string
          fecha_fin: string
          dias: number
          motivo: string | null
          doc_profesional: string | null
          doc_colegiatura: string | null
          doc_fecha: string | null
          aprobada: boolean
          registrada_tarde: boolean
          registrada_por_nombre: string | null
          registrada_at: string
          anulada: boolean
          anulada_motivo: string | null
        }[]
      }
      fn_ausencias_alerta: {
        Args: { p_persona_id?: string | null }
        Returns: {
          persona_id: string
          nombre: string
          tipo: string
          tipo_nombre: string
          veces: number
          ventana_dias: number
          umbral: number
        }[]
      }
      fn_tipos_ausencia: {
        Args: Record<PropertyKey, never>
        Returns: {
          codigo: string
          nombre: string
          paga: boolean
          requiere_documento: boolean
          requiere_aprobacion: boolean
          descuenta_vacaciones: boolean
          alerta_desde: number | null
          ventana_alerta_dias: number | null
          activo: boolean
          orden: number
        }[]
      }
      fn_costos_planilla: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      fn_planilla_congelar_pendientes: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      fn_planilla_foto_diferencias: {
        Args: { p_periodo_id: string }
        Returns: {
          persona_id: string
          nombre: string
          total_foto: number
          total_ahora: number
          diferencia: number
        }[]
      }
      fn_jornadas_extra: {
        Args: { p_desde: string; p_hasta: string; p_persona_id?: string }
        Returns: Json
      }
      fn_set_funcion: {
        Args: { p_funcion: string; p_persona_id: string }
        Returns: undefined
      }
      fn_crear_persona: {
        Args: {
          p_apellidos: string
          p_email: string | null
          p_funcion: string
          p_nombres: string
          p_pin_hash: string
          p_rol: string
          p_sede_base_id: string
        }
        Returns: Json
      }
    }
    Enums: {
      estado_jornada:
        | "abierta"
        | "en_pausa"
        | "cerrada"
        | "auto_cerrada_pendiente"
        | "revisada"
      estado_revision: "normal" | "pendiente_revision" | "revisada"
      origen_marca:
        | "terminal"
        | "admin_correccion"
        | "auto_cierre"
        | "import_historico"
      rol_usuario: "integrante" | "supervisor_sede" | "lider_do" | "admin"
      tipo_marca:
        | "entrada"
        | "salida_final"
        | "salida_almuerzo"
        | "retorno_almuerzo"
        | "salida_personal"
        | "retorno_personal"
        | "salida_tramite"
        | "retorno_tramite"
        | "salida_medico"
        | "retorno_medico"
        | "salida_otro"
        | "retorno_otro"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      estado_jornada: [
        "abierta",
        "en_pausa",
        "cerrada",
        "auto_cerrada_pendiente",
        "revisada",
      ],
      estado_revision: ["normal", "pendiente_revision", "revisada"],
      origen_marca: [
        "terminal",
        "admin_correccion",
        "auto_cierre",
        "import_historico",
      ],
      rol_usuario: ["integrante", "supervisor_sede", "lider_do", "admin"],
      tipo_marca: [
        "entrada",
        "salida_final",
        "salida_almuerzo",
        "retorno_almuerzo",
        "salida_personal",
        "retorno_personal",
        "salida_tramite",
        "retorno_tramite",
        "salida_medico",
        "retorno_medico",
        "salida_otro",
        "retorno_otro",
      ],
    },
  },
} as const

