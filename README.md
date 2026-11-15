# Modelagem Informacional - Minimundo Chaves Imóveis

## Link para a apresentação de slides
https://canva.link/ivzjo6j558c2s07

## Alunos
- Nina Leão Fonseca
- Rudá Dantas Ruoso Brandão
- Rafael Gontijo Ferreira

## Sobre o projeto

Este repositório contém as Fases 1 e 2 do trabalho (a Fase 2 está [no fim deste arquivo](#fase-2---data-lake-com-benchmark-fipezap)) de Modelagem Informacional para o minimundo **Chaves Imóveis**. A entrega cobre:

1. **MIR** - Modelagem Informacional de Requisitos (Objetivos Informacionais,
   Interfaces e Dicionário de Itens Elementares) - `Objetivos_Informacionais.pdf`
2. **Banco Operacional (OLTP)** - modelo relacional + massa de dados de exemplo
   - pasta `db_operacional/`
3. **Data Warehouse (DW)** - modelado em duas variantes de esquema dimensional
   - pastas `db_pontes/` e `db_pulverizada/`
4. **ETL** - scripts de carga inicial e incremental, do banco operacional para
   o DW - dentro de cada pasta de DW
5. **Dashboard** - visualização analítica em cima dos dados do DW -
   `dashboard.xlsx`

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
├── Chaves_Imoveis.pdf                 # slides da apresentação (PDF; versão online no link acima)
├── MIR-CHA.pdf                        # MIR (versão dos slides)
├── Objetivos_Informacionais.pdf       # MIR completo (Objetivos, Interfaces, Dicionário)
├── dashboard.xlsx                     # dashboard (tabelas dinâmicas) consumindo os dados do DW
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
├── db_fase2/  etl_python/  run_pipeline.sh  requirements.txt   # Fase 2 (ver abaixo)
│
└── data_lake/gold/                    # export em CSV do conteúdo atual do DW (modelo pulverizado) + views da Fase 2
    ├── corretor_dimension.csv, cliente_dimension.csv, imovel_dimension.csv, data_dimension.csv
    ├── trans_venda_fact.csv, receita_agregada_fact.csv
    └── vw_venda_vs_mercado.csv, mercado_fipezap_dimension.csv
```

---

## Pré-requisitos

- **PostgreSQL** (14+) instalado localmente, com acesso via `psql`
- **Microsoft Excel** (para abrir `dashboard.xlsx`)
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

(troque `cha_db` pelo nome que preferirem - só usem o mesmo nome em todos os passos seguintes)

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

**Modelo Pontes** (alternativa, usado só na Fase 1):

```sql
\i db_pontes/CHA_DDL_create_dw_db.sql
\i db_pontes/CHA_ETL_carga_inicial.sql
```

**Modelo Pulverizado** (recomendado - é o que a Fase 2 estende e o que está exportado em `data_lake/gold/`):

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
-- modelo pulverizado: cada lado (comprador/vendedor) soma a comissão inteira
SELECT SUM(tv_comissao_cliente) FROM dw_cha_pulverizado.Trans_Venda_FACT WHERE tv_tipo_cliente = 'VENDEDOR';
-- modelo pontes
SELECT SUM(tv_comissao) FROM dw_cha.Trans_Venda_FACT;
-- os dois devem bater com SUM(TransComissao) do operacional
```

### 6. Exportar os dados do DW para CSV (opcional - já incluído em `data_lake/gold/`)

```sql
SET search_path = dw_cha_pulverizado;

\copy corretor_dimension TO 'data_lake/gold/corretor_dimension.csv' WITH CSV HEADER
\copy cliente_dimension TO 'data_lake/gold/cliente_dimension.csv' WITH CSV HEADER
\copy imovel_dimension TO 'data_lake/gold/imovel_dimension.csv' WITH CSV HEADER
\copy data_dimension TO 'data_lake/gold/data_dimension.csv' WITH CSV HEADER
\copy trans_venda_fact TO 'data_lake/gold/trans_venda_fact.csv' WITH CSV HEADER
\copy receita_agregada_fact TO 'data_lake/gold/receita_agregada_fact.csv' WITH CSV HEADER
```

### 7. Abrir o Dashboard

Abram `dashboard.xlsx` no Excel. Ele consome os dados via tabelas dinâmicas
(Pivot Tables). Se os CSVs em `data_lake/gold/` tiverem sido regenerados no passo
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
- `Chaves_Imoveis.pdf` - slides de apresentação do trabalho (versão online no link do topo)
- `MIR-CHA.pdf` - MIR em formato de apresentação
---

## Fase 2 - Data Lake com benchmark FipeZAP


**Fonte externa:** [Índice FipeZAP](https://www.fipe.org.br/pt-br/indices/fipezap/) (Fipe, público) - série histórica mensal do preço médio anunciado de venda (R$/m²) de apartamentos prontos, por cidade (56) e por número de dormitórios.

**Conexão com o minimundo:** cada venda do DW recebe o R$/m² de mercado da mesma cidade, mesmo mês e mesma faixa de dormitórios. A medida derivada `agio_vs_mercado = tv_valor_m2 / mk_preco_m2 - 1` mostra quanto cada corretor/cidade vende acima (+) ou abaixo (−) do mercado.

**Pergunta de negócio:** vendemos acima ou abaixo do R$/m² anunciado no mercado da cidade, no mês da venda?
### Camadas do Data Lake

| Camada | Onde | Conteúdo |
|---|---|---|
| **Bronze** (bruto) | `data_lake/bronze/fipezap/` | planilha original da Fipe, inalterada |
| | `data_lake/bronze/oper_cha/` | snapshot CSV das tabelas do OLTP (linhagem da fonte interna) |
| **Silver** (limpo / conformado) | `data_lake/silver/fipezap_preco_m2.csv` | formato longo (cidade, cidade normalizada, mês, dormitórios, R$/m², variações) |
| | `dw_cha_pulverizado.stg_fipezap` + estrela `dw_cha_pulverizado` | staging e modelo dimensional (Fase 1 + `Mercado_FIPEZAP_DIMENSION`) |
| **Gold** (consumo) | `data_lake/gold/` | CSVs do DW + `vw_venda_vs_mercado` + mercado das cidades em que atuamos → `dashboard.xlsx` |

```
 Fipe xlsx ─► bronze/fipezap ─(etl_python)─► silver/fipezap_preco_m2.csv ─\copy─► dw_cha_pulverizado.stg_fipezap ─┐
 OLTP oper_cha ─► bronze/oper_cha (snapshot)                                                        │
      └──────(ETL Fase 1)──► dw_cha_pulverizado (estrela) ◄──(ETL Fase 2)─────────────────────────────┘
                                   └─► vw_venda_vs_mercado ─\copy─► gold/*.csv ─Power Query─► dashboard.xlsx
```

Mudanças no DW (`db_fase2/`, no modelo Pulverizado):
- nova `Mercado_FIPEZAP_DIMENSION` (grão: cidade × mês × dormitórios; Tipo 1, porque a Fipe revisa a série);
- `Imovel_DIMENSION` + `im_tipo`, `im_qtd_quartos`, `im_m2` (SCD Tipo 2 no incremental);
- `Trans_Venda_FACT` + `tv_valor_m2` e FK `mk_SK` (repetidos em todas as linhas de cliente da mesma venda);
- view `vw_venda_vs_mercado`: uma linha por **venda** (`DISTINCT ON tv_ID`), para o ágio médio não pesar a venda pelo número de clientes; traz corretor e total de compradores/vendedores.

### Execução

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
createdb cha_db
PYTHON=.venv/bin/python ./run_pipeline.sh cha_db    # Fase 1 + Fase 2 do zero, gera bronze/silver/gold
```

Para cargas seguintes, coloque a nova planilha da Fipe em `data_lake/bronze/fipezap/`, recarregue `stg_fipezap` a partir da silver e rode `db_pulverizada/CHA_ETL_carga_incremental_pulverizado.sql` seguido de `db_fase2/CHA_F2_ETL_carga_incremental.sql` (os dois são idempotentes).

### Regras de junção
- cidade: `fn_norm_cidade()` (sem acento, maiúsculo) nos dois lados;
- mês: mês da `TransVendaData` = `mk_mes` (dia 1);
- dormitórios: 1D..4D (4D = 4+), com fallback para `Total` se a cidade não tiver quebra (ex.: Vitória);
- só `ImovelTipo = 'Apartamento'` (o FipeZAP mede apartamentos prontos); os demais tipos ficam com `mk_SK` NULL.

### Modelo de dados do dashboard

A view `vw_venda_vs_mercado` expõe as chaves (`cor_sk`, `im_sk`, `dt_sk`, `mk_sk`) para que o Power Pivot relacione uma linha por venda com as dimensões:

| Origem (view) | Destino |
|---|---|
| `vw_venda_vs_mercado[cor_sk]` | `corretor_dimension[cor_sk]` |
| `vw_venda_vs_mercado[im_sk]` | `imovel_dimension[im_sk]` |
| `vw_venda_vs_mercado[dt_sk]` | `data_dimension[dt_sk]` |
| `vw_venda_vs_mercado[mk_sk]` | `mercado_fipezap_dimension[mk_sk]` |

Medidas DAX sugeridas:

```dax
Ágio médio = AVERAGE(vw_venda_vs_mercado[agio_vs_mercado])
R$/m² nosso = AVERAGE(vw_venda_vs_mercado[tv_valor_m2])
R$/m² mercado = AVERAGE(vw_venda_vs_mercado[mk_preco_m2])
Vendas com benchmark = COUNT(vw_venda_vs_mercado[agio_vs_mercado])
```

Observação: não relacionar o FipeZAP por data; usar `mk_sk`; o eixo de mês dos gráficos de benchmark é `mercado_fipezap_dimension[mk_mes]`; não misturar medidas da view com `SUM` da `trans_venda_fact` (1 linha por cliente).

### Massa de dados
O DML da Fase 1 foi ajustado para a comparação fazer sentido: o m² dos apartamentos foi recalculado a partir do FipeZAP (ágio-alvo entre −15% e +20%) e 6 imóveis em cidades cobertas viraram apartamentos. Os **valores** das vendas não mudaram, então faturamento e comissão da Fase 1 continuam iguais. Resultado: 16 de 29 vendas com benchmark.

### Limitações
- O FipeZAP é preço **anunciado**, não de transação.
- Petrópolis e Ouro Preto não existem no índice; casas, sítios, salas e terrenos ficam sem benchmark.
- O modelo Pontes (`db_pontes/`) fica só como histórico da Fase 1 e não foi estendido na Fase 2.
