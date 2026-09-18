# Modelagem Informacional - Minimundo Chaves Imóveis

## Link para a apresentação de slides
https://canva.link/ivzjo6j558c2s07

## Alunos
- Nina Leão Fonseca
- Rudá Dantas Ruoso Brandão
- Rafael Gontijo Ferreira

## Sobre o projeto

Este repositório contém a Fase 1 do trabalho de Modelagem Informacional para o minimundo **Chaves Imóveis**. A entrega cobre:

1. **MIR** - Modelagem Informacional de Requisitos (Objetivos Informacionais,
   Interfaces e Dicionário de Itens Elementares) - `Objetivos_Informacionais.pdf`
2. **Banco Operacional (OLTP)** - modelo relacional + massa de dados de exemplo
   - pasta `db_operacional/`
3. **Data Warehouse (DW)** - modelado em duas variantes de esquema dimensional
   - pastas `db_pontes/` e `db_pulverizada/`
4. **ETL** - scripts de carga inicial e incremental, do banco operacional para
   o DW - dentro de cada pasta de DW
5. **Dashboard** - visualização analítica em cima dos dados do DW -
   `Dashboard.xlsx`

Os dois modelos de DW representam a mesma informação, mas resolvem de forma diferente o relacionamento N:N entre transação de venda e clientes (compradores/vendedores):

| Modelo | Pasta | Como resolve clientes N:N |
|---|---|---|
| **Pontes** | `db_pontes/` | Tabelas ponte (`Vendedor_PONTE`, `Comprador_PONTE`) ligando `Trans_Venda_FACT` a `Cliente_DIMENSION` |
| **Pulverizado** | `db_pulverizada/` | Uma linha de fato por (transação × cliente), com a coluna `tv_tipo_cliente` indicando `COMPRADOR` ou `VENDEDOR` |

---

## Estrutura do projeto

```
MI-Projeto-CHA-main/
├── README.md                          # este arquivo
├── CHA.pptx                           # apresentação/slides do trabalho
├── Objetivos_Informacionais.pdf       # MIR completo (Objetivos, Interfaces, Dicionário)
├── Dashboard.xlsx                     # dashboard (tabelas dinâmicas) consumindo os dados do DW
│
├── db_operacional/                    # banco OLTP (schema oper_cha)
│   ├── CHA_DDL_create_oper_db.sql     # cria o schema e as tabelas operacionais
│   └── CHA_DML_populate_oper_db.sql   # popula o operacional com massa de dados de exemplo
│
├── db_pontes/                         # DW - modelo com tabelas ponte (schema dw_cha)
│   ├── CHA_DDL_create_dw_db.sql              # cria o schema do DW e as tabelas (fato, dimensões, pontes)
│   ├── CHA_ETL_carga_inicial.sql             # ETL: primeira carga completa OLTP -> DW
│   └── CHA_ETL_carga_incremental.sql         # ETL: cargas subsequentes (idempotente, SCD Tipo 2)
│
├── db_pulverizada/                    # DW - modelo pulverizado (schema dw_cha_pulverizado)
│   ├── CHA_DDL_create_dw_db_pulverizado.sql        # cria o schema do DW e as tabelas (fato pulverizada, dimensões)
│   ├── CHA_ETL_carga_inicial_pulverizado.sql       # ETL: primeira carga completa OLTP -> DW pulverizado
│   └── CHA_ETL_carga_incremental_pulverizado.sql   # ETL: cargas subsequentes (idempotente, SCD Tipo 2)
│
├── db_diagramas/                      # diagramas fonte (editáveis em erdplus.com)
│   ├── CHA_ER.erdplus                 # diagrama Entidade-Relacionamento do operacional
│   ├── CHA_Relacional.erdplus         # esquema relacional do operacional
│   ├── CHA_FACT.erdplus               # esquema estrela do DW - modelo pontes
│   └── CHA_FACT_pulverizado.erdplus   # esquema estrela do DW - modelo pulverizado
│
└── data/                              # export em CSV do conteúdo atual do DW (modelo pontes)
    ├── corretor_dimension.csv
    ├── cliente_dimension.csv
    ├── imovel_dimension.csv
    ├── data_dimension.csv
    ├── trans_venda_fact.csv
    ├── vendedor_ponte.csv
    ├── comprador_ponte.csv
    └── receita_agregada_fact.csv
```

---

## Pré-requisitos

- **PostgreSQL** (14+) instalado localmente, com acesso via `psql`
- **Microsoft Excel** (para abrir `Dashboard.xlsx`)
- Opcional: conta em [erdplus.com](https://erdplus.com) para visualizar/editar
  os arquivos `.erdplus`

---

## Como construir e executar

Todos os scripts assumem que operacional e DW ficam **no mesmo banco de dados**, em schemas diferentes (`oper_cha`, `dw_cha` e/ou `dw_cha_pulverizado`). Cada DDL já faz `DROP SCHEMA ... CASCADE` seguido de `CREATE SCHEMA`, então os scripts podem ser executados do zero quantas vezes
forem necessárias.

### 1. Criar/conectar o banco

```bash
createdb cha_db
psql -d cha_db
```

(troque `cha_db` pelo nome que preferirem - só usem o mesmo nome em todos os
passos seguintes)

### 2. Construir o banco operacional

Dentro do `psql`, conectados em `cha_db`:

```sql
\i db_operacional/CHA_DDL_create_oper_db.sql
\i db_operacional/CHA_DML_populate_oper_db.sql
```

Confirme que populou certo:

```sql
SET search_path = oper_cha;
SELECT COUNT(*) FROM TransVenda;
```

### 3. Construir o Data Warehouse

Escolham **um** dos dois modelos (ou rodem os dois, já que ficam em schemas
separados e não conflitam entre si).

**Modelo Pontes** (recomendado - é o que está exportado em `data/`):

```sql
\i db_pontes/CHA_DDL_create_dw_db.sql
\i db_pontes/CHA_ETL_carga_inicial.sql
```

**Modelo Pulverizado** (alternativa, sem tabelas ponte):

```sql
\i db_pulverizada/CHA_DDL_create_dw_db_pulverizado.sql
\i db_pulverizada/CHA_ETL_carga_inicial_pulverizado.sql
```

### 4. (Opcional) Simular uma nova carga incremental

Depois de alterar algo no operacional (ex.: `UPDATE` no orçamento de um
corretor, um novo `INSERT` em `TransVenda`), rodem o ETL incremental
correspondente ao modelo escolhido - ele é idempotente, ou seja, pode ser
executado várias vezes sem duplicar dados:

```sql
-- modelo pontes
\i db_pontes/CHA_ETL_carga_incremental.sql

-- ou modelo pulverizado
\i db_pulverizada/CHA_ETL_carga_incremental_pulverizado.sql
```

### 5. Validar o DW

```sql
SET search_path = dw_cha;  -- ou dw_cha_pulverizado

SELECT SUM(tv_comissao) FROM Trans_Venda_FACT;  -- deve bater com SUM(TransComissao) do operacional
```

### 6. Exportar os dados do DW para CSV (opcional - já incluído em `data/`)

```sql
SET search_path = dw_cha;

\copy corretor_dimension TO 'data/corretor_dimension.csv' WITH CSV HEADER
\copy cliente_dimension TO 'data/cliente_dimension.csv' WITH CSV HEADER
\copy imovel_dimension TO 'data/imovel_dimension.csv' WITH CSV HEADER
\copy data_dimension TO 'data/data_dimension.csv' WITH CSV HEADER
\copy trans_venda_fact TO 'data/trans_venda_fact.csv' WITH CSV HEADER
\copy vendedor_ponte TO 'data/vendedor_ponte.csv' WITH CSV HEADER
\copy comprador_ponte TO 'data/comprador_ponte.csv' WITH CSV HEADER
\copy receita_agregada_fact TO 'data/receita_agregada_fact.csv' WITH CSV HEADER
```

### 7. Abrir o Dashboard

Abram `Dashboard.xlsx` no Excel. Ele consome os dados via tabelas dinâmicas
(Pivot Tables). Se os CSVs em `data/` tiverem sido regenerados no passo
anterior, atualizem as tabelas dinâmicas em **Dados → Atualizar Tudo** (ou
clique com o botão direito sobre a tabela dinâmica → **Atualizar**) para
refletir os dados mais recentes.

---

## Diagramas

Os arquivos `.erdplus` em `db_diagramas/` podem ser importados diretamente em
[erdplus.com](https://erdplus.com) (**File → Import**) para visualização e
edição:

- `CHA_ER.erdplus` - modelo Entidade-Relacionamento do operacional
- `CHA_Relacional.erdplus` - esquema relacional do operacional
- `CHA_FACT.erdplus` - esquema estrela do DW (modelo pontes)
- `CHA_FACT_pulverizado.erdplus` - esquema estrela do DW (modelo pulverizado)

## Documentação adicional

- `Objetivos_Informacionais.pdf` - MIR completo: Objetivos Informacionais por ator, Interfaces Informacionais de Requisitos e Dicionário de Itens Elementares, além dos Objetivos Organizacionais com seus fluxogramas
- `CHA.pptx` - slides de apresentação do trabalho
