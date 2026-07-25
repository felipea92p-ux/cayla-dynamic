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
          actualizado_por?: string | null
          actualizado_at?: string
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
      personas: {
        Row: {
          apellidos: string
          auth_user_id: string | null
          created_at: string
          documento: string | null
          email: string | null
          en_planilla: boolean
          estado: string
          sueldo_fijo: boolean
          fecha_estado_cambio: string | null
          fecha_ingreso: string
          funcion: string
          id: string
          nombres: string
          pin_hash: string
          rol: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
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
          sueldo_fijo?: boolean
          fecha_estado_cambio?: string | null
          fecha_ingreso?: string
          funcion?: string
          id?: string
          nombres: string
          pin_hash: string
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
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
          sueldo_fijo?: boolean
          fecha_estado_cambio?: string | null
          fecha_ingreso?: string
          funcion?: string
          id?: string
          nombres?: string
          pin_hash?: string
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id?: string
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
        }
        Insert: {
          activa?: boolean
          codigo: string
          id?: string
          nombre: string
        }
        Update: {
          activa?: boolean
          codigo?: string
          id?: string
          nombre?: string
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
        }
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
        Args: { p_codigo: string; p_nombre: string }
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
      fn_set_visible_todas_sedes: {
        Args: { p_persona_id: string; p_valor: boolean }
        Returns: undefined
      }
      fn_set_mi_firma: {
        Args: { p_dataurl: string | null }
        Returns: undefined
      }
      fn_firma_persona: {
        Args: { p_persona_id: string }
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

