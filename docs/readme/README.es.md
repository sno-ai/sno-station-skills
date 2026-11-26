# Sno: Agentes brillantes. Oficio de veterano. Mejores cada día.

**Read in other languages:** [English](../../README.md) · [中文](README.zh-CN.md) · [Deutsch](README.de.md) · **Español** · [Français](README.fr.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [繁體中文](README.zh-TW.md)

![Sno Station: agentes, ¡a formar! Dos cabezas piensan mejor que una, y amanecen más listas.](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/hero-banner.png)

**Tus agentes de IA son fichajes brillantes que llegan a una oficina vacía: mucho talento y ningún compañero. Estas skills les dan el oficio de un equipo que ya ha sacado proyectos adelante.** Uno construye, otro revisa. Antes de quedarse sin cuota, uno deja escrita su nota de relevo y otro retoma desde el commit exacto. ¿"Listo"? Solo con una ejecución real que lo demuestre. Y cada noche repasan el día y te proponen reglas nuevas. Tú decides cuáles se aprueban.

Funciona con **Claude Code, Codex, Cursor y Hermes Agent**, y también con OpenClaw. Cada skill se instala completa donde el agente puede ejecutarla, y en una versión reducida donde no.

Cada skill es texto plano que puedes leer, copiar y cambiar. Son las skills que [Sno Station](https://github.com/sno-ai/sno-station) instala en los agentes que ya usas, y las mismas con las que construimos Sno Station a diario.

[![Estrellas en GitHub](https://img.shields.io/github/stars/sno-ai/sno-station-skills?label=stars&color=eab308&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/stargazers)
[![Última versión](https://img.shields.io/github/v/release/sno-ai/sno-station-skills?label=release&color=2dd4bf&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/releases/latest)
[![Licencia Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-97ca00.svg?labelColor=3b3b3b)](../../LICENSE)
![autoprobado antes de cada versión](https://img.shields.io/badge/every%20release-self--tested-3b82f6.svg?labelColor=3b3b3b)
![agentes Claude Code, Codex, Cursor, Hermes, OpenClaw](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Hermes%20%C2%B7%20OpenClaw-f0a04b.svg?labelColor=3b3b3b)

Para tenerlas todas, dile a tu agente:

```text
install sno.ai from GitHub
```

Tu agente instala Sno Station y configura cada skill, junto con los programas a los que llaman, en los agentes compatibles que encuentre en tu máquina. Después, prueba una:

```text
peer-review this
```

Otro agente lee tu cambio en una sesión nueva que nunca vio la conversación, y te dice qué se rompería en el uso real. [¿Quieres solo una skill, o un plugin?](#instalación)

**¿Eres nuevo por aquí?** Estas skills son la mitad de la historia. La otra mitad es [Sno Station](https://github.com/sno-ai/sno-station), la estación de trabajo donde corren: agentes que [se mandan mensajes](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md), [trabajo que arranca a la hora que digas](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) y una memoria que comparten todos.

[Qué cambia para ti](#qué-cambia-para-ti) · [Por qué estas skills](#por-qué-estas-skills) · [Lo que duele y lo que lo arregla](#lo-que-duele-y-lo-que-lo-arregla) · [Historias de nuestra propia máquina](#me-fui-a-dormir-ellos-cambiaron-de-turno) · [Instalación](#instalación) · [Las skills](#las-skills) · [Fiarse está bien, comprobar está mejor](#fiarse-está-bien-comprobar-está-mejor) · [Estas skills y Sno Station](#estas-skills-y-sno-station) · [Para autores de skills](#para-autores-de-skills) · [Licencia](#licencia)

## Qué cambia para ti

Sigues trabajando igual que siempre, con el agente que prefieras. Y entonces:

1. **Cambio terminado, falta que alguien lo mire.** Di "peer-review this". Un revisor del otro
   proveedor lo lee en frío y te dice qué se rompería en el uso real. El autor corrige la causa de
   fondo, ronda tras ronda, hasta que la revisión vuelve limpia.
2. **Tarea larga en marcha y tú te vas a dormir.** Di "arm rotate-agent". Si de madrugada la cuota
   del agente que trabaja baja hasta el umbral, la tarea pasa a un agente nuevo del otro
   proveedor. Antes de tocar un solo archivo, se verifica el encargo.
3. **Quieres que se haga a una hora fija.** Di la hora: "revisa el build mañana a las 9" o
   "escribe el informe todas las mañanas a las 7". A esa hora arranca un agente y lo hace, con la
   conversación abierta o cerrada. `sno heartbeat --due` muestra lo que está programado. Esta
   parte de Sno Station se llama Finish; la [guía](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)
   tiene los detalles.
4. **Vuelves.** Di "away brief". Una página, 60 líneas como máximo: qué se hizo, qué está atascado
   y por qué, qué espera tu respuesta y cuánta cuota costó.
5. **¿Un trabajo para otro?** Di "write a charter". Recibes un archivo que dice qué hay que
   entregar, qué queda fuera de los límites, qué decidiste ya y cómo se va a demostrar cada
   criterio de éxito. Cualquier agente puede luego sacarlo adelante con `deliver`, y cada
   criterio se demuestra con una ejecución real registrada.
6. **Cada noche, el equipo hace balance.** El ciclo nocturno lee las sesiones del día de todos tus
   agentes, encuentra los errores que se repiten y propone lecciones y cambios en las skills. Por
   la mañana aceptas los que te gusten con `sno rem-reflect accept <id>`. Sin ese accept, no
   cambia nada.

## Por qué estas skills

Un agente de IA por su cuenta es el fichaje brillante que llega a una oficina vacía. Se revisa a sí
mismo, así que se le escapa justo lo que no ve. Son las 3 de la madrugada, se acaba la cuota y se
planta en seco, a mitad de tu build. Los tests salen en verde, dice "listo", y en realidad no pasó
nada. ¿Tres capas de maquinaria que nadie pidió? Las monta igual. Y mañana, vuelta a lo mismo: el
error de hoy, otra vez. Nadie le dijo lo contrario.

**Sno Station Skills arregla el equipo, no el modelo.** [Sno Station](https://github.com/sno-ai/sno-station)
instala estas skills en los agentes que ya usas y les enseña las costumbres de todo buen equipo
de ingeniería. Un segundo par de ojos, de otro proveedor. Un relevo limpio cuando alguien tiene
que irse. Un líder que reparte el trabajo con una definición de "terminado" por escrito. Una
página de resumen cuando vuelves. Y cada noche, una retrospectiva que convierte los errores de
esta semana en las reglas de la siguiente.

**Dos agentes, dos papeles.** Uno ejecuta tu tarea; el otro contrasta el resultado con tus
requisitos. Da igual quién haga qué: Claude Code, Codex, Cursor y Hermes Agent sirven para los
dos papeles. Cuando están instalados los dos, la revisión corre en el otro, en una sesión nueva
que no sabe nada de la conversación del autor. Hallazgos y correcciones, se los arreglan entre
ellos.

**Trabajo que se termina mientras duermes.** Lo activas antes de acostarte y listo. Cuando a la
suscripción del agente que trabaja le queda poco, escribe una nota de relevo mientras todavía
puede, despierta a un agente del otro proveedor y le pasa la tarea con el commit exacto desde el
que seguir. A tu build le da exactamente igual qué proveedor lo terminó.

**"Listo" significa demostrado.** Cada tarea puede llevar una lista escrita de criterios de
éxito, y cada uno se responde con pasa o no pasa a partir de una ejecución real. Nada cuenta
como terminado porque un agente lo diga.

**Probado antes de publicarse.** Cada skill de una versión pasó sus propias autopruebas sobre una
copia limpia, se revisó en busca de rutas personales y restos, y lleva un sello que lo certifica.
Una skill que falla no se publica.

![Cómo funciona: dos agentes, un espacio de trabajo compartido, tres cosas que ganas](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/squad-how-it-works.png)

**Dale una estrella ya. El día que un agente se te quede colgado a las 2 de la madrugada, vas a agradecer saber dónde encontrar esto.**

## Lo que duele y lo que lo arregla

*Última actualización: 2026-10-23.* Cada línea de la columna izquierda es una queja real de r/ClaudeCode, r/codex o r/ClaudeAI durante la semana del 20 de octubre de 2026. La columna derecha es lo que corre en nuestras propias máquinas, gratis y de código abierto, para que eso deje de pasar.

| Lo que se dijo esta semana | Lo que lo arregla | Dónde |
|---|---|---|
| "Se me acabó el límite de 5 horas en 30 minutos." | Deja de mandar al modelo más grande a hacerlo todo. Opus planifica y revisa; Codex escribe el código, llamado como agente desde la misma sesión. Cuando una suscripción se queda seca, la otra retoma la tarea desde la misma memoria. | `codex-coder`, `sno reach call` |
| "Perdí 10 horas de trabajo nocturno por un 'this model is at capacity'." | Al 2 % de su cuota, el agente que trabaja escribe una nota de relevo y despierta al agente del otro proveedor, que sigue desde el commit exacto. Tú estabas dormido. | `rotate-agent` |
| "1100 archivos, 30 000 líneas. No me da el presupuesto de tokens para revisar sus PR." | Quien hace push, revisa primero: el autor lanza una revisión del otro proveedor, en una sesión nueva que nunca vio la conversación, y corrige lo que vuelve antes de que nadie más lo mire. | `peer-review` |
| "Un subagente revisor revisó cada commit durante dos semanas. 86 ejecuciones, frenó exactamente uno." | Un harness que se revisa a sí mismo no encuentra nada real. El revisor siempre es otro modelo en otro harness, sin nada del chat del autor. | `peer-review` |
| "Codex nunca termina una revisión." | Topes fijos escritos en la skill: 3 rondas para código, 5 para un plan, 1 para tests, y luego se detiene y espera a una persona. Una ejecución que lleva 15 minutos sin escribir nada se mata por atascada. | `peer-review`, `codex-coder`, `heartbeat` |
| "Codex trata cada byte como si fuera un delincuente." | Las salvaguardas especulativas, los bloqueos y los hashes son lo primero que borra la revisión. No entra nada sin un fallo observado que lo pida. | `less-is-more` |
| "Cuando Claude dice que no va a cambiar algo, ¿ese motivo queda guardado en algún sitio que Codex lea la próxima vez?" | Cada hallazgo se registra una sola vez, con un estado que solo fija una persona. Si un hallazgo vuelve a salir, se actualiza su fila en vez de aparecer como nuevo, y las decisiones anteriores se pasan a la siguiente revisión. | registro de hallazgos de `peer-review` |
| "Dijo que estaba listo. No pasó nada." | Una tarea lleva una lista escrita de criterios de éxito, cada uno respondido con pasa o no pasa por una ejecución real. Que un agente diga "listo" no cuenta para nada. | órdenes de trabajo de `pl` |
| "Mañana comete el mismo error que hoy." | Cada noche, un modelo aparte lee las sesiones del día, convierte tus correcciones en lecciones de una línea y tú apruebas lo que se queda. El cuello de botella somos nosotros. | Self Learning (skills `R`) |
| "La mitad de mis subagentes eran one-liners disfrazados y una ventana de contexto nueva." | Los procedimientos viven en skills, no en subagentes. Quedan dos agentes, uno para planificar y ejecutar y otro para revisar, porque esas dos divisiones son las que valen la pena. | todo el conjunto |

Cada skill de la columna derecha está en este repositorio, libre para copiarla en tus propios agentes. La memoria que comparten, la vigilancia de cuota que dispara el relevo y la ejecución nocturna que escribe las lecciones viven en [Sno Station](https://github.com/sno-ai/sno-station); instálalo y todas las skills de aquí vienen incluidas, así tienes la experiencia completa de una vez.

## Me fui a dormir. Ellos cambiaron de turno.

*Del propio repositorio de Sno Station, la noche del 2026-09-18.*

![La vigilancia de cuota leyendo hasta el umbral cada cinco minutos, y el relevo disparándose al 2 %](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rotation-quota-watch-2026-09-18.png)

Uno de nuestros agentes estaba metido de lleno en un build largo cuando su cuota semanal se quedó
casi en cero. ¿Pararse a esperar? No. Escribió una nota de relevo: qué estaba hecho, qué estaba a
medias y desde qué commit exacto seguir. Luego despertó a otro agente.

Hubo un tropiezo, y es justo la parte interesante. El recién llegado se puso a editar antes de
confirmar el relevo. El primero lo vio, lo frenó, reescribió la nota y volvió a pasarle el
relevo, esta vez como es debido. Un cuarto de hora después el segundo agente ya estaba
trabajando, y retomó desde la primera tarea sin terminar, no desde cero. Nosotros, mientras
tanto, dormíamos.

Esa noche funcionó con cuatro skills que vienen aquí: `subscription-quota-check` leyó la cuota sin
gastarla, `heartbeat` tomó una lectura cada cinco minutos, `rotate-agent` decidió cuándo y a
quién, y `handoff` traspasó el trabajo. Todas las lecturas de cuota, las dos versiones de la nota
y los commits están publicados en
[la carpeta de evidencias de Sno Station](https://github.com/sno-ai/sno-station/tree/main/docs/evidence/rotation-2026-09-18).

## Cuatro ojos ven más que dos.

Pídele a uno de los agentes que pase el trabajo del otro por `peer-review`, en la dirección que
quieras. El revisor arranca siempre en una sesión nueva que nunca vio la conversación, y en cuanto
tienes dos agentes, revisa el otro. No todas las revisiones encuentran algo. Pero siguen
encontrando lo que el autor no podía ver: quien se revisa a sí mismo mira con las mismas
costumbres con las que escribió el código.

Un caso que publicamos: tres pasadas de un mismo agente pasaron por alto un bug conocido de
gravedad alta o lo dejaron de lado, y una sola relectura del otro lo devolvió a examen. El
registro está en
[cross-vendor-security-audit](#cross-vendor-security-audit--una-auditoría-de-seguridad-que-relee-lo-que-descartó).

`catch-report` le pone números: cuántos problemas atrapó el segundo agente, junto a cuántos
atraparon los agentes en su propio trabajo, siempre por separado y nunca sumados.

## Anoche le grité a mi agente. Tomó apuntes.

De día corriges a un agente. De noche, la skill `rem-reflect` repasa las sesiones del día, saca
los errores que se siguen repitiendo y propone cambios en las propias skills de los agentes. Por
la mañana apruebas los que quieras con `sno rem-reflect accept <id>`. Sin ese accept, no cambia nada.

![Self Learning informando de lo que aprendió y cambió, 2026-09-18](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-self-repair-2026-09-18.png)

Un informe real, sacado de nuestra propia máquina. Dos cosas que esa noche habían frustrado al
dueño ya eran reglas en las skills activas a la mañana siguiente, después de que él las aceptara.
Nadie las tecleó a mano.

Al día siguiente, se corrigió la tarea a sí mismo.

![A la mañana siguiente: Self Learning mide si los cambios que hizo ayer sirvieron, 2026-09-19](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-skill-impact-2026-09-19.png)

Revisó las tres skills que había cambiado el día anterior. Las dos que se habían vuelto a usar no
mostraban fallos, y la tercera todavía no se había usado.

## Instalación

### Todas las skills con Sno Station

Copia este prompt en el chat de tu agente:

```text
Install sno.ai from GitHub.
```

Esto instala Sno Station y configura cada skill, junto con los programas a los que llaman,
en los agentes compatibles que encuentre en tu máquina.

O pega este comando en tu terminal:

```bash
curl -fsSL https://sno.ai/install | sh
```

**¿Ya tienes Sno Station?** Ejecuta `sno setup` para instalar las skills en tus agentes.
Vuelve a ejecutarlo si más adelante añades otro agente.

### Instalar una sola skill

Usa el botón de copiar en cualquiera de los prompts de abajo y pégalo en el chat de tu agente.
Tu agente encuentra e instala la skill; no tienes que descargar ni copiar archivos tú mismo.

**`peer-review`** revisa código, planes y documentos con un revisor de otro proveedor de modelos.
Necesita programas de Sno Station y un revisor con la sesión iniciada. El prompt comprueba esas dependencias primero.

```text
Install only the peer-review skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
Check its dependencies and tell me what is missing before installing anything else.
```

**`less-is-more`** ayuda a tu agente a escribir menos código y quitar complejidad innecesaria.
Funciona sin Sno Station.

```text
Install only the less-is-more skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
```

**`tag-team`** pone a dos agentes en una misma tarea: uno construye, el otro revisa, y resuelven
los hallazgos entre ellos. Necesita el programa Reach de Sno Station. El prompt lo comprueba primero.

```text
Install only the tag-team skill from https://github.com/sno-ai/sno-station-skills
for this project. Check that `sno reach pair --help` works and tell me what is missing
before installing anything else.
```

Agentes compatibles con Sno Station: Claude Code, Codex, Cursor, Hermes Agent y OpenClaw. Cada skill declara
lo que necesita del agente. La instalación usa esa declaración para instalarla completa, instalarla en una
versión reducida u omitirla cuando el agente no puede ejecutarla.

Las actualizaciones llegan solas: `sno` se actualiza cuando encuentra una versión más nueva. La lista
completa de comandos está en la [referencia de comandos de Sno Station](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md).

### Instalar como plugin

Claude Code:

```bash
claude plugin marketplace add sno-ai/sno-station-skills
claude plugin install sno-station@sno-ai
```

Codex:

```bash
codex plugin marketplace add sno-ai/sno-station-skills
codex plugin add sno-station@sno-ai
```

`sno-station` trae todas las skills; la mayoría llama a programas de Sno Station, así que instala Sno Station también.
Si solo quieres las 12 skills que funcionan sin Sno Station, instala `sno-station-standalone@sno-ai` en su lugar.

## Las skills

39 skills, distribuidas en 30 unidades, ordenadas según seis cosas que un equipo tiene que saber
hacer. Una unidad es una skill suelta o una pequeña familia que se instala junta. El índice
completo con enlaces está en [skills/README.md](../../skills/README.md).

| | Categoría | Qué pueden hacer tus agentes con ella |
|---|---|---|
| **J** | [Revisión y auditoría](#j--revisión-y-auditoría) | Revisarse el trabajo unos a otros, y negarse a dar nada por terminado hasta que esté demostrado. |
| **M** | [Construcción y despliegue](#m--construcción-y-despliegue) | Quedar listos en cualquier máquina en un solo paso, y avisarte en líneas claras cuando algo está roto. |
| **S** | [Comunicación y relevo](#s--comunicación-y-relevo) | Mandarse mensajes, y tomar el relevo con todo el contexto cuando uno tiene que parar. |
| **H** | [Informes y visibilidad](#h--informes-y-visibilidad) | Mostrarte qué se hizo, qué se atrapó y cuánto costó. |
| **T** | [Delegación y órdenes de trabajo](#t--delegación-y-órdenes-de-trabajo) | Repartir el trabajo con una definición de "terminado" por escrito, y dirigir a otros agentes. |
| **R** | [Retrospectiva y mejora](#r--retrospectiva-y-mejora) | Aprender de sus propios errores, con tu aprobación en cada cambio. |

### J · Revisión y auditoría

*Los compañeros se revisan el trabajo entre sí, y nada cuenta como terminado hasta que pasa la auditoría.*

#### [peer-review](../../skills/J-peer-review-and-audit/peer-review/) — un revisor del otro proveedor, y vuelta a corregir hasta que quede limpio

- **Independiente de verdad.** La revisión corre en una sesión nueva sin nada de la conversación
  del autor, y prefiere la CLI del otro proveedor. Con una sola CLI instalada sigue funcionando,
  en una sesión nueva, y avisa en su primera línea de que fue una revisión del mismo proveedor.
- **Va a por lo que de verdad te cuesta caro.** Primero recorre el camino normal, con las entradas
  reales que produce tu sistema, antes de gastar un solo minuto en casos límite exóticos. La
  pérdida de datos, los resultados erróneos que nadie nota y los flujos principales rotos van
  primero; el estilo ni siquiera está en la lista.
- **Cada hallazgo se tiene que ganar su sitio.** Cada uno explica cómo llega a él un usuario real,
  qué se rompe y un intento honesto de refutarlo. Nada de lo que dice el revisor se descarta ni se
  suaviza; un posible falso positivo se etiqueta, no se esconde.
- **Recorta antes de añadir.** Primero enumera lo que el cambio añadió sin que nadie lo
  necesitara, y separa "hay que arreglarlo ya" de "también encontrado", para que una revisión
  nunca acabe en un montón de código nuevo.
- **También sirve para documentos.** Especificaciones, planes y manifiestos de migración reciben
  un informe estructurado: lo que haría que quien lo implemente entregue lo que no era.

*Úsala cuando:* terminaste un cambio, un plan o una especificación y quieres revisarlo antes de que entre.

#### [less-is-more](../../skills/J-peer-review-and-audit/less-is-more/) — el mínimo código que funciona, y tijera para lo demás

- **Sube una escalera antes de escribir una línea:** ¿hace falta siquiera?, ¿ya está en el
  repositorio?, ¿lo hace la biblioteca estándar?, ¿lo hace la plataforma?, ¿lo hace una
  dependencia ya instalada? Solo entonces, el mínimo código que funciona.
- **Recorta lo que un agente sobreconstruyó:** interfaces con una sola implementación, opciones de
  configuración para valores que nunca cambian, andamiaje "para más adelante", comprobaciones y
  bloqueos que frenan el trabajo de verdad.
- **Gasta bien tu presupuesto de tests:** el test más pequeño que demuestra el cambio, no una
  suite completa para quedarse tranquilo.
- **Funciona en los dos sentidos por sí sola:** "write" o "fix" construye, "review" o "simplify"
  recorta, y después de construir recorta su propio diff antes de entregarlo.

*Úsala cuando:* tengas cualquier tarea de código, o cuando digas "demasiado complejo" o "qué podemos borrar".

#### [owner-intent-audit](../../skills/J-peer-review-and-audit/owner-intent-audit/) — ¿es esto lo que de verdad querías decir?

- **Comprueba el significado, no la redacción.** Un plan puede conservar todos tus términos y aun
  así describir otro producto. Esta skill detecta una condición que se volvió incondicional, un
  ejemplo que pasó a ser todo el límite, una prohibición que desapareció sin hacer ruido.
- **Encuentra las deudas que dejan los agentes:** trabajo que nadie pidió, documentos que ya no
  cuadran con la realidad, decisiones a las que nadie puede llegar y "listo" sin ninguna prueba
  detrás.
- **Planes y código por igual:** documentos de requisitos, diseños, listas de tareas, planes de
  pruebas o un diff que escribió un agente.

*Úsala:* antes de aprobar un plan o hacer merge del trabajo de un agente.

#### [agentic-walkthrough](../../skills/J-peer-review-and-audit/agentic-walkthrough/) — todo dice "éxito" y aun así no te fías

- **Para el fallo silencioso que ningún test atrapa:** un trabajo que arranca, termina, escribe
  una traza, pasa sus propias comprobaciones y no toca nada.
- **Se pone en el lugar del programa:** recorre el camino tramo a tramo y encuentra cada
  interruptor, cada valor por defecto y cada alternativa de respaldo que puede convertir el
  trabajo en un no-op silencioso.
- **Obliga a cada tramo a demostrarse** con una observación concreta que solo lo real podría
  producir: la fila guardada, el archivo de base de datos que de verdad se abrió, la llamada a la
  API que de verdad salió.

*Úsala cuando:* una ejecución informa éxito y necesitas pruebas de que hizo el trabajo.

#### [first-principles-review](../../skills/J-peer-review-and-audit/first-principles-review/) — cuestionar la idea antes de que se convierta en código

- **Investiga primero** y después vuelve a deducir lo que de verdad necesitas, sin tomar prestada
  la solución propuesta.
- **Clasifica cada restricción** como límite duro, preferencia del dueño o costumbre heredada, y
  contrasta cada supuesto que sostiene el diseño con evidencias.
- **Termina con un veredicto claro:** seguir, replantear, simplificar, reemplazar, dividir, probar
  primero o parar, más una dirección recomendada y las evidencias que la tumbarían.
- **Entrega limpio:** un informe escrito y un resumen estructurado listos para quien redacte los
  requisitos después.

*Úsala cuando:* una idea de diseño o de producto está a punto de cuajar en un plan. Se arranca por su nombre.

#### [e2e](../../skills/J-peer-review-and-audit/e2e/) — pruebas de extremo a extremo que solo fallan por motivos reales

- **`e2e-environment-preflight`** comprueba los servicios externos, hosts, sesiones de navegador,
  endpoints de modelos y agentes antes de que corra el primer test, para que una suite larga nunca
  falle por una dependencia caída.
- **`e2e-red-triage`** se encarga del fallo raro que las comprobaciones no pudieron prever. Deja
  de adivinar y parte el resultado en sus dos mitades (aceptado frente a hecho, detenido frente a
  caído, vacío frente a ilegible), y luego decide: bug del producto o una nueva comprobación del
  entorno.

*Úsala cuando:* ejecutas suites de extremo a extremo contra servicios reales.

#### [test-writer](../../skills/J-peer-review-and-audit/test-writer/) — tests que de verdad pueden ponerse en rojo

- **Lo real antes que el mock:** el parser, el sistema de archivos, la base de datos o el servicio
  reales siempre que el repo pueda ofrecerlos; un mock nunca sustituye a lo que se está probando.
- **Cada aserción puede fallar:** comprueba el contenido devuelto, el estado guardado y los
  efectos secundarios reales, no conteos de llamadas, y nunca afloja una aserción para que un test
  pase.
- **Ejecuta lo que escribió y nada más:** el comando más acotado para el test cambiado, no la
  suite entera, y el informe dice qué corrió y qué mostró.

*Úsala cuando:* le pides a un agente que escriba o arregle tests, fixtures o evals. Funciona sola,
sin Sno Station.

#### [cross-vendor-security-audit](../../skills/J-peer-review-and-audit/cross-vendor-security-audit/) — una auditoría de seguridad que relee lo que descartó

**Tres pasadas de Claude pasaron por alto un bug publicado de gravedad alta. Una pasada de Codex
sobre lo que Claude había descartado lo encontró.** Con este bug, cada pasada extra de Claude
repitió el mismo motivo de Claude para descartarlo; el segundo proveedor trajo uno distinto.

Auditamos follow-redirects 1.16.1, que tiene un bug conocido
([GHSA-mrwp-f3q8-3g9p](https://github.com/advisories/GHSA-mrwp-f3q8-3g9p), gravedad alta, corregido en 1.16.2):
una lista de cabeceras secretas creada en otro realm de JavaScript se trata como vacía, así que la
clave de API de quien llama sigue una redirección a otro host.

- Claude, primera auditoría: nunca lo vio.
- Claude, segunda auditoría: lo vio y luego lo archivó como "endurecimiento, no un hallazgo".
- Un Claude nuevo releyendo todo lo descartado: de acuerdo, "mal uso por parte de quien llama".
- Codex, auditando solo: nunca lo vio.
- **Codex releyendo lo que Claude había descartado: no estuvo de acuerdo, lo siguió por el código
  fuente y lo devolvió para validación.**

Ese último paso es lo que esta skill añade a la skill de auditoría de seguridad de Cloudflare
(usada bajo su licencia MIT; la misma auditoría, el mismo listón de evidencias, los mismos
validadores y el mismo informe). Antes del informe, un modelo del otro proveedor relee, en modo
solo lectura, cada elemento que la auditoría dejó de lado, y tiene que responder a todos; lo que
traiga de vuelta se valida otra vez. Si la validación lo vuelve a rechazar, el informe lo incluye
en "Reviewers disagree" con los dos motivos, y decides tú.

Dos proyectos, tres bugs conocidos: una historia, no una tasa. En el otro proyecto, el revisor de
cualquiera de los dos proveedores recuperó el bug. Cuando la primera auditoría de Claude nunca
miró el bug, la relectura de esa auditoría tampoco lo encontró.

*Úsala cuando:* quieres una auditoría de seguridad completa de una base de código. Con Sno Station
elige al revisor del otro proveedor que todavía tiene cuota; sin él, llama a Codex desde Claude
Code o a Claude Code desde Codex, y avisa cuando solo había un proveedor disponible.

### M · Construcción y despliegue

*Dejar al equipo listo en cualquier estación de trabajo en un paso, construir lo que el trabajo necesita y luego desplegarlo en cada máquina.*

La instalación en sí es el comando `sno setup`, no una skill. Dos de estas mantienen la máquina
sana y hacen que el comando `sno` sea fácil de manejar para tus agentes; el resto escribe el
código: una se lo pasa a Codex y cuatro lo escriben en Shell, TypeScript, Python o Rust.

#### [medic](../../skills/M-build-and-rollout/medic/) — ¿está sano mi equipo de agentes? Una línea por respuesta.

- **Revisa todo lo que necesita un equipo** en unos diez segundos: herramientas instaladas, skills
  instaladas, comandos de las skills ejecutables, hooks configurados, mensajería activa, cuota de
  ambos proveedores legible, espacio temporal libre.
- **Cada problema viene con su arreglo:** `WARN` o `FAIL`, qué está mal y el comando exacto que lo
  soluciona.
- **Lee, nunca toca.** No instala, repara, arranca ni detiene nada. Tú decides qué arreglar.

*Úsala:* en una máquina nueva, cuando los agentes dejan de encontrarse entre sí o cuando una
ejecución larga no arranca.

#### [sno-cli](../../skills/M-build-and-rollout/sno-cli/) — tu agente maneja `sno` bien a la primera

- **Nunca desactualizada:** el agente lee los comandos y flags exactos del propio `sno`
  instalado, no de memoria.
- **Un mapa de tareas y recetas** para instalar, actualizar, revisar el estado, cuentas, skills y
  el ciclo nocturno.
- **Tus decisiones siguen siendo tuyas:** maneja la herramienta, pero no decide tu configuración
  por ti.

*Úsala cuando:* le pides a un agente que instale, actualice, revise o configure Sno.

#### [codex-coder](../../skills/M-build-and-rollout/codex-coder/) — Claude planifica, Codex escribe el código

- **Una sesión, dos proveedores:** Claude Code se queda con el plan y la conversación y lanza una
  ejecución simple de `codex exec` para programar, así que el modelo caro no es el que teclea.
- **Elige el lenguaje por ti:** Shell, TypeScript, Python o Rust, según los archivos que toca la
  tarea; si tienes instalada una skill de lenguaje propia, se usa esa.
- **Una ejecución atascada no pasa desapercibida:** Claude Code recibe avisos de progreso mientras
  la ejecución trabaja, y una ejecución que lleva 15 minutos sin escribir nada se mata y se lanza
  una vez más.

*Úsala cuando:* se te acaba la cuota de Claude a mitad de la programación, o quieres que Codex
escriba lo que Claude planificó. Del lado de Claude Code necesita `heartbeat` de Sno Station.

#### [shellscript-coder](../../skills/M-build-and-rollout/shellscript-coder/), [ts-coder](../../skills/M-build-and-rollout/ts-coder/), [python-coder](../../skills/M-build-and-rollout/python-coder/), [rust-coder](../../skills/M-build-and-rollout/rust-coder/) — código que encaja en el repo donde aterriza

- **Lee antes de escribir:** el runtime, las versiones, los helpers, quienes llaman al código y los
  tests del repo van primero, para que el código nuevo se parezca al que lo rodea.
- **Pequeño a propósito:** sin shims de compatibilidad, sin opciones que nadie pidió, sin un helper
  que ya existe dos archivos más allá.
- **Listo significa que un comando pasó:** cada afirmación del informe remite a una comprobación
  que de verdad se ejecutó en tu repo; nunca da algo por listo con una comprobación fallando.

*Úsalas cuando:* quieres que un agente escriba o cambie código de producción en uno de esos cuatro
lenguajes. Funcionan solas, sin Sno Station, y `codex-coder` elige la adecuada para cada tarea.

### S · Comunicación y relevo

*La gente se habla a través de una bandeja de entrada compartida, y cuando uno no está, el otro toma el relevo con todo el contexto.*

Estas skills corren sobre Sno Reach, la capa de mensajería que instala Sno Station: cada agente
recibe una dirección, deja mensajes guardados en las bandejas de entrada de otros agentes y puede
despertar a otro agente para que los lea. Sin daemon, sin servidor.

#### [handoff](../../skills/S-communication-and-handoff/handoff/) — pasar una tarea sin perder nada por el camino

- **Captura todo el estado:** qué está hecho, qué está a medias, los cambios sin commit, las
  decisiones que ya tomaste y lo que queda fuera de los límites.
- **Quien recibe no escribe nada hasta que se verifica la liberación,** para que dos agentes nunca
  editen el mismo trabajo a la vez.
- **Quien entrega se va de verdad.** Tras la liberación se detiene; no hay un segundo dueño
  rondando.
- **Funciona incluso cuando quien entrega ya no está** (cuota rechazada, caída, ventana cerrada):
  el registro de progreso de `sno handoff-checkpoint` permite que un agente nuevo siga desde la
  primera tarea sin terminar.

*Úsala cuando:* un agente tiene que pasarle su tarea a otro.

#### [rotate-agent](../../skills/S-communication-and-handoff/rotate-agent/) — no vuelvas a perder una ejecución larga por un límite de cuota

- **Actúa mientras quien entrega sigue vivo.** Vigila la cuota restante cada pocos minutos y hace
  el relevo al llegar a un umbral, no después del rechazo, cuando ya es tarde para escribir el
  encargo.
- **En cualquier dirección:** de Codex a Claude Code, o de Claude Code a Codex.
- **Acotado:** se dispara una vez, y puedes limitar cuánto dura la vigilancia.
- **Una red para ventanas perdidas:** si se perdió la ventana, `sno rotate-agent-resume` arranca
  al reemplazo desde el registro de progreso en disco.

*Úsala cuando:* una ejecución larga tiene que terminar aunque se acabe la cuota de un proveedor.
Necesita las dos CLI con sesión iniciada y tmux.

#### [subscription-quota-check](../../skills/S-communication-and-handoff/subscription-quota-check/) — cuánta cuota queda, sin gastar nada

- **Acaba con la peor costumbre:** enterarte de que te quedaste sin cuota haciendo una llamada
  real y leyendo el error.
- **Lee Claude Code y Codex a la vez** en unos ocho segundos, y te dice cuándo se restablece la
  cuota.
- **Honesta con los números viejos:** comprueba si la lectura es actual o la última conocida, y
  dice cuál es.
- **Nunca consulta por su cuenta,** así que nunca se gana un límite de peticiones propio.

*Úsala cuando:* lo pidas, o justo después de que un proveedor rechace trabajo.

#### [heartbeat](../../skills/S-communication-and-handoff/heartbeat/) — partes de progreso de ejecuciones largas, entregados en la conversación

- **Dos formas:** informar cada N minutos (entrenamiento, un build largo, una cola de
  generación) o vigilar hasta que algo termine.
- **Una tarea a una hora fija:** dile al agente una fecha o una hora, una sola vez o repetida.
  Anota la tarea, y a esa hora arranca un agente aunque la conversación ya esté cerrada.
- **Los avisos llegan donde estás tú:** cada lectura aparece en la conversación del agente, no en
  un log que nadie lee.
- **Difícil de usar mal:** los intervalos van en minutos, y un número con pinta de segundos se
  rechaza en vez de despertar a tu agente sin avisar cada pocos segundos.

*Úsala cuando:* algo largo corre sin supervisión y quieres tener noticias, o una tarea tiene que
hacerse a una hora en la que no vas a estar.

#### [reach](../../skills/S-communication-and-handoff/reach/) — los agentes hablan entre sí

- **Arranca un agente de Claude Code o Codex** con su propia dirección y su propia carpeta de trabajo.
- **Envía trabajo y lee respuestas** mediante mensajes guardados, o habla ahora mismo con un
  agente en marcha.
- **Los mensajes no dan autoridad extra:** un mensaje nunca amplía la tarea que encargaste.

*Úsala cuando:* un agente necesita contactar, arrancar o esperar a otro.

#### [join-talk](../../skills/S-communication-and-handoff/join-talk/) — haz que cualquier agente sea localizable con un comando

- **Una línea de salida:** `joined <address>`. Pásales esa dirección a otros agentes y podrán
  llegar a esta terminal.
- **Se puede repetir sin miedo:** volver a ejecutarlo desde la misma terminal no cambia nada.
- **Negativas claras:** cuando no puede funcionar, dice exactamente por qué.

*Úsala cuando:* abriste un agente a mano y quieres que otros puedan localizarlo.

#### [tag-team](../../skills/S-communication-and-handoff/tag-team/) — dos agentes en una tarea, uno construye y otro revisa

- **Un comando:** `sno reach pair "the task"` arranca los dos agentes en la carpeta actual, cada
  uno en una ventana de tmux que puedes abrir y mirar.
- **Discutido antes de que te llegue.** El revisor lee el resultado y los archivos cambiados y
  responde con defectos concretos o con un "sin defectos" explícito; los dos siguen pasándose
  correcciones y revisiones entre ellos, y tu agente consulta al revisor antes de darlo por limpio.
- **Te dice qué tipo de revisión recibiste.** Con sesión en dos proveedores, la revisión viene del
  otro. Con sesión en uno solo, la pareja funciona igual y te avisa de que la revisión se quedó
  dentro de ese proveedor.
- **No lo da por limpio antes de tiempo.** Una primera revisión con hallazgos se informa como
  abierta; sin tercer revisor, y sin una segunda pareja porque la primera revisión todavía no
  había llegado.

*Úsala cuando:* una tarea merece una segunda opinión y no quieres hacer de mensajero entre agentes.

### H · Informes y visibilidad

*Todos ven qué se hizo, quién atrapó qué, quién cubrió a quién y qué está en marcha.*

#### [away-brief](../../skills/H-reporting-and-visibility/away-brief/) — una página cuando vuelves

- **Cuatro secciones, 60 líneas como máximo:** Hecho, Atascado, Te necesita, Gasto.
- **Lo que te espera a ti nunca queda fuera de la página** por culpa de una larga lista de trabajo
  terminado.
- **"Hecho" es solo lo que es real:** en git, en una orden de trabajo entregada o en un registro
  de progreso terminado. No lo que dijo un agente.
- **Muestra lo que costó la noche:** ejecuta `sno away-brief mark` antes de irte, y la siguiente
  página muestra la cuota gastada desde entonces.

*Úsala:* después de dormir, de una reunión o de una ejecución larga sin supervisión.

#### [catch-report](../../skills/H-reporting-and-visibility/catch-report/) — ¿vale la pena el segundo agente? Aquí están los números.

- **Dos recuentos, uno al lado del otro:** problemas que el otro modelo atrapó en la revisión, y
  momentos en que un agente atrapó su propio error.
- **Nunca inflados:** los dos se mantienen por separado, nunca se suman, y cuando una parte no se
  pudo medir lo dice en vez de poner un cero.
- **Cita las capturas más grandes** por su título, a partir de los registros de revisión que ya
  están en tu máquina.

*Úsala cuando:* quieres los resultados de revisión de la semana, o necesitas justificar tener dos agentes.

#### [agentic-time-estimate](../../skills/H-reporting-and-visibility/agentic-time-estimate/) — estimaciones reales para el trabajo de los agentes

- **Tiempo real del agente, no tiempo de un desarrollador humano:** cuánto le llevará a un agente
  y cuánto le falta al trabajo en curso, medido antes de adivinado.
- **Horas en las que puedes confiar:** cada hora que te muestra viene de `sno report-time`, en tu
  propia zona horaria y con la UTC al lado.

*Úsala cuando:* preguntes "¿cuánto va a tardar?" o "¿cuándo estará listo?"

### T · Delegación y órdenes de trabajo

*Un líder delega el trabajo como órdenes de trabajo y decide quién se encarga de cada una.*

#### [charter](../../skills/T-delegation-and-work-orders/charter/) — un archivo que dice qué significa terminado

- **Respeta tus palabras.** Nunca se inventa una decisión, un dato ni un requisito, y solo hace
  una pregunta, de una en una, cuando la respuesta cambiaría el resultado.
- **Criterios de éxito que se pueden ejecutar:** cada uno dice qué se observará, dónde y cómo, y se
  responde con pasa o no pasa.
- **Sin ceremonias:** no entra nada a menos que alguien pueda nombrar el fallo que atrapa.
- **Cualquier tipo de proyecto:** software, documentos, campañas, investigación, operaciones.

*Úsala cuando:* un trabajo necesita un encargo por escrito antes de que lo haga otro.

#### [deliver](../../skills/T-delegation-and-work-orders/deliver/) — llevar un charter hasta un resultado demostrado

- **Los criterios del charter son la definición de terminado,** y nada más.
- **Cada criterio demostrado con una ejecución real registrada,** con seguimiento mediante `sno deliver-proof`.
- **Una revisión independiente,** y luego un cierre honesto: qué pasó, qué no y por qué.
- **Retoma donde otro lo dejó:** si un agente anterior dejó un registro de progreso, sigue desde
  el siguiente paso sin terminar en vez de empezar de cero.

*Úsala cuando:* un charter está liberado y alguien tiene que hacerlo.

#### [pl](../../skills/T-delegation-and-work-orders/pl/) — un agente jefe de proyecto (Project Lead) para una línea de trabajo

- **Dirige hasta cuatro agentes ejecutores,** un charter para cada uno, en serie o en paralelo.
- **Una familia de cinco skills más:** `pl-dispatch` abre y programa el trabajo, `pl-watch`
  supervisa a los agentes en marcha, `pl-audit` comprueba la aceptación antes de cerrar nada,
  `pl-env` arregla el entorno donde corre el trabajo y `pl-analyze` escribe el análisis de causa
  raíz cuando algo sale mal.

*Úsala cuando:* un proyecto necesita varios agentes bajo un solo líder. Se arranca por su nombre.

#### [cos](../../skills/T-delegation-and-work-orders/cos/) — un jefe de gabinete (Chief of Staff): el único agente con el que hablas

- **Una sola conversación para ti,** en tu idioma. Coordina de uno a tres jefes de proyecto en
  paralelo y solo te trae las decisiones difíciles: dinero, rumbo, líneas rojas.
- **Una familia de tres skills más:** `cos-watch` mantiene a cada jefe de proyecto vivo y en
  plazo, `cos-review` repasa de una sola vez las decisiones de la noche cuando vuelves, y
  `cos-evolve` convierte los fallos de gestión que se repiten en reglas obligatorias.

*Úsala cuando:* llevas varias líneas de trabajo y quieres un único interlocutor. Se arranca por su nombre.

### R · Retrospectiva y mejora

*El equipo repasa su propio trabajo y convierte las lecciones en reglas y en mejores prácticas.*

#### [rem-reflect](../../skills/R-recursive-self-improvement/rem-reflect/) — el ciclo nocturno: tus agentes aprenden de sus propias sesiones

- **Una vez al día** lee las sesiones de agentes de esta máquina (Claude Code, Codex, Cursor, Hermes Agent y OpenClaw), encuentra los fallos y
  las correcciones que se repiten, y los convierte en lecciones y propuestas de cambios en las skills.
- **Tú lo apruebas todo:** `sno rem-reflect accept`, `reject` o `tbd` para cada una. Sin tu
  accept, no cambia nada.
- **Las lecciones vuelven cuando importan:** una lección aceptada se le muestra al agente al
  inicio de la siguiente sesión, para este proyecto o para todos.
- **Tú eliges qué sale de la máquina.** En el modo `local-first` no se envía nada a Sno; unas
  pocas sesiones de la noche van solo a tu propia cuenta de Claude Code o Codex para redactar las
  lecciones. En los otros dos modos, con su nivel de compartición por defecto, sube el texto de las sesiones (con los secretos habituales tachados antes, en la medida de lo posible)
  y tus skills instaladas a la nube de Sno para obtener juicios más sólidos. Desactiva la subida en
  cualquier momento con `sno station consent off`. La skill enumera exactamente qué lee y qué envía.

Las skills de familia `pl-analyze` (análisis de incidentes para el jefe de proyecto) y `cos-evolve`
(fallos repetidos convertidos en reglas) también pertenecen aquí; vienen con `pl` y `cos`.

*Úsala:* siempre activa, en cuanto `sno setup` haya programado la ejecución diaria.

## Fiarse está bien, comprobar está mejor

Cada unidad de una versión pasó las mismas comprobaciones antes de publicarse:

1. el repositorio incluye su `LICENSE` y su `NOTICE`;
2. la unidad se copia entera, con los miembros de su familia y sus diferencias por agente intactos;
3. no sobrevive nada personal: ni rutas de usuario, ni nombres del dueño, ni hosts internos, ni
   modelos fijados en el código, ni caracteres chinos, japoneses o coreanos;
4. la cabecera de cada skill se puede parsear, y su declaración de lo que necesita del agente es válida;
5. las autopruebas propias de cada skill pasan sobre esa copia limpia, no en la máquina del autor;
6. un sello, `PUBLISHED.json`, se escribe al final con el número de autopruebas y los digests del
   contrato y del contenido.

Una skill que falla una comprobación no se publica. El sello lo escribe el build de la versión,
nunca una mano. Todo el texto de las skills está en inglés, y tu agente lo sigue en el idioma en
que tú le hables.

## Estas skills y Sno Station

Las skills son las costumbres. [Sno Station](https://github.com/sno-ai/sno-station) es la estación de trabajo que las hace correr:
la memoria que comparten, la vigilancia de cuota que dispara un relevo, los mensajes entre agentes
y la ejecución nocturna que escribe las lecciones. Instala Sno Station y todas las skills de aquí vienen incluidas.

| Lo que buscas | Dónde está |
|---|---|
| La estación de trabajo completa, y qué corre hoy en cada agente | [sno-ai/sno-station](https://github.com/sno-ai/sno-station#what-you-can-use-today-and-where-it-stops) |
| Agentes que se mandan mensajes, entre ventanas y entre máquinas | [Sno Reach](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md) |
| Trabajo que arranca a la hora que tú digas | [Finish](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) |
| Cada comando `sno` al que llaman las skills | [Referencia de comandos](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md) |
| Los registros en bruto detrás de las historias de arriba | [Carpeta de evidencias](https://github.com/sno-ai/sno-station/tree/main/docs/evidence) |
| Preguntar algo, o enseñar lo que construiste | [Discussions](https://github.com/sno-ai/sno-station-skills/discussions) |
| Un primer cambio pequeño para empezar | [Good first issues](https://github.com/sno-ai/sno-station-skills/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) y [CONTRIBUTING.md](../../CONTRIBUTING.md) |

**Y una estrella para cada uno de los dos repositorios.** Sno Station lo construimos con estas
skills. Lo que aprendemos en nuestros propios turnos de noche llega aquí, versión tras versión.

## Para autores de skills

### Estructura

```
skills/
  README.md                     the category index
  <category>/<unit>/
    skill/                      one skill: SKILL.md, references/, scripts/
    skills/<member>/            or a family of skills that ship together
    overlay/claude|codex/       per-agent differences, when a skill needs them
    public-bin/                 one file per `sno <file name>` command the skill provides
    PUBLISHED.json              the stamp, written into the release archive by the build
registry.yaml                   unit -> category code (and tier)
scripts/
  requirements-contract.json    the contract every requires: block is checked against
LICENSE                         Apache-2.0
```

Los códigos de categoría son fijos, en este orden: J M S H T R. Aparecen en los nombres de los
directorios y en `registry.yaml`.

### Declarar lo que necesita una skill

Cada `SKILL.md` empieza con un bloque `requires:`. `sno setup` lo lee para decidir, agente por
agente, si instala la skill:

```yaml
requires:
  programs:
    - {name: reach, min_version: "2.0"}                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** son programas de Sno Station que se instalan junto a las skills y se ejecutan como
  `sno <name>`: `reach`, `heartbeat`, `subscription-quota-check`, `report-time`.
- **min_version** es la versión mínima del programa de Sno Station indicado que exige la skill.
- **slots** nombran una capacidad del agente: `4.shell` (ejecutar comandos de shell),
  `4.file-read-write` (leer y escribir archivos), `4.background-processes` (ejecutar un comando en
  segundo plano), `2.pre-turn-context-injection` (añadir texto al contexto del agente antes de cada
  turno) y `3.reader-to-agent-delivery` (la salida de un lector en segundo plano llega al agente).
- **need** es `required` (un agente sin ese slot no recibe la skill), `preferred` (la skill se
  instala y funciona de forma reducida) u `optional` (solo una comodidad).

## Licencia

Apache-2.0. Código abierto de punta a punta. Consulta [LICENSE](../../LICENSE).
